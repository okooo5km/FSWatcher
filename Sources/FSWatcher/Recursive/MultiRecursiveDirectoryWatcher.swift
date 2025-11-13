//
//  MultiRecursiveDirectoryWatcher.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation
import Combine

/// A watcher that can monitor multiple directories recursively simultaneously
public class MultiRecursiveDirectoryWatcher {
    
    // MARK: - Properties
    
    private var watchers: [URL: RecursiveDirectoryWatcher] = [:]
    private let options: RecursiveWatchOptions
    private let configuration: DirectoryWatcher.Configuration
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
    
    /// Initialize a multi-recursive directory watcher
    /// - Parameters:
    ///   - options: Options for recursive watching (applied to all directories)
    ///   - configuration: Configuration for individual watchers
    public init(options: RecursiveWatchOptions = RecursiveWatchOptions(), configuration: DirectoryWatcher.Configuration = DirectoryWatcher.Configuration()) {
        self.options = options
        self.configuration = configuration
    }
    
    deinit {
        stopAllWatching()
    }
    
    // MARK: - Public Methods
    
    /// Start watching multiple directories recursively
    /// - Parameter directories: The directories to watch
    public func startWatching(directories: [URL]) {
        for directory in directories {
            startWatching(directory: directory)
        }
    }
    
    /// Start watching a single directory recursively
    /// - Parameter directory: The directory to watch
    public func startWatching(directory: URL) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        // Check if already watching
        guard watchers[directory] == nil else { return }
        
        do {
            let watcher = try RecursiveDirectoryWatcher(
                url: directory,
                options: options,
                configuration: configuration
            )
            
            // Set up event forwarding
            watcher.onDirectoryChange = { [weak self] url in
                self?.handleDirectoryChange(url)
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
            watchers[directory] = watcher
            
        } catch {
            if let fsError = error as? FSWatcherError {
                onError?(fsError)
            } else {
                onError?(FSWatcherError.cannotOpenDirectory(directory))
            }
        }
    }
    
    /// Stop watching a specific directory
    /// - Parameter directory: The directory to stop watching
    public func stopWatching(directory: URL) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        if let watcher = watchers.removeValue(forKey: directory) {
            watcher.stop()
        }
    }
    
    /// Stop watching all directories
    public func stopAllWatching() {
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
    
    /// Get the list of currently watched root directories
    public var watchedDirectories: [URL] {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        return Array(watchers.keys)
    }
    
    /// Get all watched directories (including subdirectories) across all root directories
    public var allWatchedDirectories: [URL] {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        var allDirectories: [URL] = []
        for (_, watcher) in watchers {
            allDirectories.append(contentsOf: watcher.watchedDirectories)
        }
        return allDirectories
    }
    
    /// Check if any directories are being watched
    public var isWatching: Bool {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        return !watchers.isEmpty && watchers.values.contains { $0.isWatching }
    }
    
    /// Check if a specific directory is being watched
    /// - Parameter directory: The directory to check
    /// - Returns: true if the directory is being watched
    public func isWatching(directory: URL) -> Bool {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        return watchers[directory]?.isWatching ?? false
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
    }
    
    /// Add a filter to a specific directory watcher
    /// - Parameters:
    ///   - filter: The filter to add
    ///   - directory: The directory whose watcher should receive the filter
    public func addFilter(_ filter: FileFilter, to directory: URL) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        watchers[directory]?.addFilter(filter)
    }
    
    /// Clear all filters from all watchers
    public func clearAllFilters() {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        for (_, watcher) in watchers {
            watcher.clearFilters()
        }
    }
    
    // MARK: - Ignore List Management
    
    /// Add files to ignore across all watchers
    /// - Parameter urls: The URLs to ignore
    public func addIgnoredFiles(_ urls: [URL]) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        for (_, watcher) in watchers {
            watcher.addIgnoredFiles(urls)
        }
    }
    
    /// Add files to ignore for a specific directory
    /// - Parameters:
    ///   - urls: The URLs to ignore
    ///   - directory: The directory whose watcher should ignore the files
    public func addIgnoredFiles(_ urls: [URL], in directory: URL) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        watchers[directory]?.addIgnoredFiles(urls)
    }
    
    /// Add files for predictive ignoring across all watchers
    /// - Parameter urls: The URLs to predictively ignore
    public func addPredictiveIgnore(_ urls: [URL]) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        for (_, watcher) in watchers {
            watcher.addPredictiveIgnore(urls)
        }
    }
    
    /// Add files for predictive ignoring for a specific directory
    /// - Parameters:
    ///   - urls: The URLs to predictively ignore
    ///   - directory: The directory whose watcher should predictively ignore the files
    public func addPredictiveIgnore(_ urls: [URL], in directory: URL) {
        watchersLock.lock()
        defer { watchersLock.unlock() }
        
        watchers[directory]?.addPredictiveIgnore(urls)
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

