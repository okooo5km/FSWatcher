//
//  DirectoryWatcher.swift
//  FSWatcher
//
//  Created by FSWatcher on 2025/08/13.
//

import Foundation
import Combine

/// A watcher that monitors changes in a single directory
public class DirectoryWatcher {
    
    // MARK: - Configuration
    
    /// Configuration for directory watching
    public struct Configuration {
        /// The debounce interval to prevent rapid firing of events
        public var debounceInterval: TimeInterval = 0.5
        
        /// The file system events to monitor
        public var eventMask: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename]
        
        /// The dispatch queue for event handling
        public var queue: DispatchQueue = .global(qos: .utility)
        
        /// Filter chain for filtering events
        public var filterChain: FilterChain = FilterChain()
        
        /// Ignore list for managing ignored files
        public var ignoreList: IgnoreList = IgnoreList()
        
        /// Transform predictor for predicting output files
        public var transformPredictor: FileTransformPredictor?
        
        public init() {}
    }
    
    // MARK: - Properties
    
    private let url: URL
    private var configuration: Configuration
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let debouncer: DebounceTimer
    private var _isWatching = false
    private let watchingLock = NSLock()
    
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
    
    /// Initialize a new directory watcher
    /// - Parameters:
    ///   - url: The URL of the directory to watch
    ///   - configuration: The configuration for watching
    /// - Throws: FSWatcherError if initialization fails
    public init(url: URL, configuration: Configuration = Configuration()) throws {
        self.url = url
        self.configuration = configuration
        self.debouncer = DebounceTimer(interval: configuration.debounceInterval, queue: configuration.queue)
        
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
    
    /// Start watching the directory
    public func start() {
        watchingLock.lock()
        defer { watchingLock.unlock() }
        
        guard !_isWatching else { return }
        
        // Open the directory
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            let error = FSWatcherError.cannotOpenDirectory(url)
            onError?(error)
            return
        }
        
        // Create the dispatch source
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: configuration.eventMask,
            queue: configuration.queue
        )
        
        // Set up event handler
        source?.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }
        
        // Set up cancellation handler
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        
        // Start monitoring
        source?.resume()
        _isWatching = true
    }
    
    /// Stop watching the directory
    public func stop() {
        watchingLock.lock()
        defer { watchingLock.unlock() }
        
        guard _isWatching else { return }
        
        source?.cancel()
        source = nil
        _isWatching = false
        debouncer.cancel()
        
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
        watchingLock.lock()
        defer { watchingLock.unlock() }
        return _isWatching
    }
    
    // MARK: - Filter Management
    
    /// Add a filter to the filter chain
    /// - Parameter filter: The filter to add
    public func addFilter(_ filter: FileFilter) {
        configuration.filterChain.add(filter)
    }
    
    /// Clear all filters from the filter chain
    public func clearFilters() {
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
    
    private func handleFileSystemEvent() {
        debouncer.debounce { [weak self] in
            guard let self = self else { return }
            
            // Get list of files in directory
            let filteredFiles = self.getFilteredFiles()
            
            // Notify via various mechanisms
            self.notifyDirectoryChange()
            
            if !filteredFiles.isEmpty {
                self.notifyFilteredChange(filteredFiles)
            }
        }
    }
    
    private func getFilteredFiles() -> [URL] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            return contents.filter { fileURL in
                // Check ignore list
                if configuration.ignoreList.shouldIgnore(fileURL) {
                    return false
                }
                
                // Apply filter chain
                if !configuration.filterChain.isEmpty && !configuration.filterChain.matches(fileURL) {
                    return false
                }
                
                return true
            }
        } catch {
            return []
        }
    }
    
    private func notifyDirectoryChange() {
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
    
    private func notifyFilteredChange(_ files: [URL]) {
        // Apply predictive ignoring if predictor is available
        if let predictor = configuration.transformPredictor {
            for file in files {
                let predictedOutputs = predictor.predictOutputFiles(for: file)
                if !predictedOutputs.isEmpty {
                    configuration.ignoreList.addPredictiveIgnore(predictedOutputs)
                }
            }
        }
        
        // Call closure
        onFilteredChange?(files)
        
        // Publish to Combine
        filteredChangeSubject.send(files)
        
        // Send to async streams
        continuationLock.lock()
        filteredContinuations.values.forEach { $0.yield(files) }
        continuationLock.unlock()
    }
}