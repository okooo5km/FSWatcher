//
//  RecursiveDirectoryWatcher.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation
import Combine

/// Options for recursive directory watching
public struct RecursiveWatchOptions {
    /// Maximum depth to watch (nil for unlimited)
    public var maxDepth: Int?
    
    /// Whether to follow symbolic links
    public var followSymlinks: Bool = false
    
    /// Glob patterns to exclude (e.g., "*.tmp", "node_modules")
    public var excludePatterns: [String] = []
    
    /// Initialize with default options
    public init() {}
    
    /// Initialize with custom options
    /// - Parameters:
    ///   - maxDepth: Maximum depth to watch
    ///   - followSymlinks: Whether to follow symbolic links
    ///   - excludePatterns: Patterns to exclude
    public init(maxDepth: Int? = nil, followSymlinks: Bool = false, excludePatterns: [String] = []) {
        self.maxDepth = maxDepth
        self.followSymlinks = followSymlinks
        self.excludePatterns = excludePatterns
    }
}

/// A watcher that recursively monitors directories and their subdirectories
public class RecursiveDirectoryWatcher {
    
    // MARK: - Properties
    
    private let rootURL: URL
    private let options: RecursiveWatchOptions
    private var configuration: DirectoryWatcher.Configuration
    private var watchers: [URL: DirectoryWatcher] = [:]
    private let watchersLock = NSLock()
    
    // Event handlers
    public weak var delegate: DirectoryWatcherDelegate?
    public var onDirectoryChange: ((URL) -> Void)?
    public var onFilteredChange: (([URL]) -> Void)?
    public var onError: ((FSWatcherError) -> Void)?
    
    // Combine support
    private let directoryChangeSubject = PassthroughSubject<URL, Never>()
    private let filteredChangeSubject = PassthroughSubject<[URL], Never>()
    
    // Swift Concurrency support
    private var continuations: [UUID: AsyncStream<URL>.Continuation] = [:]
    private var filteredContinuations: [UUID: AsyncStream<[URL]>.Continuation] = [:]
    private let continuationLock = NSLock()
    
    // MARK: - Initialization
    
    /// Initialize a recursive directory watcher
    /// - Parameters:
    ///   - url: The root directory to watch
    ///   - options: Options for recursive watching
    ///   - configuration: Configuration for individual watchers
    /// - Throws: FSWatcherError if initialization fails
    public init(url: URL, options: RecursiveWatchOptions = RecursiveWatchOptions(), configuration: DirectoryWatcher.Configuration = DirectoryWatcher.Configuration()) throws {
        self.rootURL = url
        self.options = options
        self.configuration = configuration
        
        // Verify the directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FSWatcherError.directoryNotFound(url)
        }
        
        guard isDirectory.boolValue else {
            throw FSWatcherError.invalidConfiguration("URL is not a directory: \(url.path)")
        }
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Start watching the directory recursively
    public func start() {
        // Scan and watch all directories
        scanAndWatchSubdirectories(at: rootURL, currentDepth: 0)
    }
    
    /// Stop watching all directories
    public func stop() {
        watchersLock.lock()
        let currentWatchers = watchers
        watchers.removeAll()
        watchersLock.unlock()
        
        for (_, watcher) in currentWatchers {
            watcher.stop()
        }
        
        // Complete all continuations
        continuationLock.lock()
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
        filteredContinuations.values.forEach { $0.finish() }
        filteredContinuations.removeAll()
        continuationLock.unlock()
    }
    
    /// Check if the watcher is currently watching
    public var isWatching: Bool {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        return !watchers.isEmpty && watchers.values.contains { $0.isWatching }
    }
    
    /// Get all watched directories
    public var watchedDirectories: [URL] {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        return Array(watchers.keys)
    }
    
    // MARK: - Filter Management
    
    /// Add a filter to all watchers
    /// - Parameter filter: The filter to add
    public func addFilter(_ filter: FileFilter) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        for (_, watcher) in watchers {
            watcher.addFilter(filter)
        }
        
        // Update configuration for future watchers
        configuration.filterChain.add(filter)
    }
    
    /// Clear all filters
    public func clearFilters() {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        for (_, watcher) in watchers {
            watcher.clearFilters()
        }
        
        configuration.filterChain.clear()
    }
    
    // MARK: - Ignore List Management
    
    /// Add files to the ignore list
    /// - Parameter urls: The URLs to ignore
    public func addIgnoredFiles(_ urls: [URL]) {
        configuration.ignoreList.addIgnored(urls)
    }
    
    /// Add files for predictive ignoring
    /// - Parameter urls: The URLs to predictively ignore
    public func addPredictiveIgnore(_ urls: [URL]) {
        configuration.ignoreList.addPredictiveIgnore(urls)
    }
    
    // MARK: - Combine Support
    
    /// Publisher for directory change events
    public var directoryChangePublisher: AnyPublisher<URL, Never> {
        directoryChangeSubject.eraseToAnyPublisher()
    }
    
    /// Publisher for filtered change events
    public var filteredChangePublisher: AnyPublisher<[URL], Never> {
        filteredChangeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Swift Concurrency Support
    
    /// Async stream of directory changes
    public var directoryChanges: AsyncStream<URL> {
        AsyncStream { continuation in
            let id = UUID()
            
            continuationLock.lock()
            continuations[id] = continuation
            continuationLock.unlock()
            
            continuation.onTermination = { [weak self] _ in
                self?.continuationLock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.continuationLock.unlock()
            }
        }
    }
    
    /// Async stream of filtered changes
    public var filteredChanges: AsyncStream<[URL]> {
        AsyncStream { continuation in
            let id = UUID()
            
            continuationLock.lock()
            filteredContinuations[id] = continuation
            continuationLock.unlock()
            
            continuation.onTermination = { [weak self] _ in
                self?.continuationLock.lock()
                self?.filteredContinuations.removeValue(forKey: id)
                self?.continuationLock.unlock()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func scanAndWatchSubdirectories(at url: URL, currentDepth: Int) {
        // Check depth limit
        if let maxDepth = options.maxDepth, currentDepth > maxDepth {
            return
        }
        
        // Check if directory should be excluded
        let directoryName = url.lastPathComponent
        for pattern in options.excludePatterns {
            if matchesGlobPattern(name: directoryName, pattern: pattern) {
                return
            }
        }
        
        // Create watcher for this directory
        watchDirectory(url)
        
        // Scan subdirectories
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                var isDirectory: ObjCBool = false
                var isSymlink = false
                
                // Check if it's a symbolic link
                if let resourceValues = try? item.resourceValues(forKeys: [.isSymbolicLinkKey]),
                   let isSymbolicLink = resourceValues.isSymbolicLink {
                    isSymlink = isSymbolicLink
                }
                
                // Skip symlinks if not following them
                if isSymlink && !options.followSymlinks {
                    continue
                }
                
                // Check if it's a directory
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    // Recursively watch subdirectory
                    scanAndWatchSubdirectories(at: item, currentDepth: currentDepth + 1)
                }
            }
        } catch {
            // Ignore errors for individual directories
        }
    }
    
    private func watchDirectory(_ url: URL) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        // Check if already watching
        guard watchers[url] == nil else { return }
        
        do {
            let watcher = try DirectoryWatcher(url: url, configuration: configuration)
            
            // Set up event forwarding
            watcher.onDirectoryChange = { [weak self] changedURL in
                self?.handleDirectoryChange(changedURL)
                
                // Check for new subdirectories
                self?.checkForNewSubdirectories(in: changedURL)
            }
            
            watcher.onFilteredChange = { [weak self] filteredURLs in
                self?.handleFilteredChange(filteredURLs)
            }
            
            watcher.onError = { [weak self] error in
                self?.onError?(error)
            }
            
            // Start watching
            watcher.start()
            
            // Store the watcher
            watchers[url] = watcher
            
        } catch {
            // Handle error silently or report it
            if let fsError = error as? FSWatcherError {
                onError?(fsError)
            }
        }
    }
    
    private func checkForNewSubdirectories(in directory: URL) {
        // Get current depth of this directory
        let depth = calculateDepth(for: directory)
        
        // Check if we should continue watching deeper
        if let maxDepth = options.maxDepth, depth >= maxDepth {
            return
        }
        
        // Scan for new subdirectories
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    
                    // Check if we're already watching this directory
                    watchersLock.lock()
                    let isWatching = watchers[item] != nil
                    watchersLock.unlock()
                    
                    if !isWatching {
                        // Start watching the new subdirectory
                        scanAndWatchSubdirectories(at: item, currentDepth: depth + 1)
                    }
                }
            }
        } catch {
            // Ignore errors
        }
    }
    
    private func calculateDepth(for url: URL) -> Int {
        let rootComponents = rootURL.pathComponents
        let urlComponents = url.pathComponents
        
        // Calculate the depth relative to root
        return max(0, urlComponents.count - rootComponents.count)
    }
    
    private func matchesGlobPattern(name: String, pattern: String) -> Bool {
        // Simple glob pattern matching
        var regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        
        // Anchor the pattern
        regexPattern = "^" + regexPattern + "$"
        
        return name.range(of: regexPattern, options: .regularExpression) != nil
    }
    
    private func handleDirectoryChange(_ url: URL) {
        // Create event
        let event = FileSystemEvent(url: url, eventType: .modified)
        
        // Notify delegate
        delegate?.directoryDidChange(with: event)
        
        // Call closure
        onDirectoryChange?(url)
        
        // Publish to Combine
        directoryChangeSubject.send(url)
        
        // Send to async streams
        continuationLock.lock()
        continuations.values.forEach { $0.yield(url) }
        continuationLock.unlock()
    }
    
    private func handleFilteredChange(_ urls: [URL]) {
        // Call closure
        onFilteredChange?(urls)
        
        // Publish to Combine
        filteredChangeSubject.send(urls)
        
        // Send to async streams
        continuationLock.lock()
        filteredContinuations.values.forEach { $0.yield(urls) }
        continuationLock.unlock()
    }
}