//
//  RecursiveDirectoryWatcher.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Combine
import Foundation

#if os(macOS)
    import CoreServices
#endif

/// Backend used by `RecursiveDirectoryWatcher`.
public enum RecursiveWatchBackend: Equatable, Sendable {
    /// Choose the lowest-resource backend for the current platform.
    ///
    /// On macOS this uses FSEvents unless `followSymlinks` is enabled. On
    /// other platforms it falls back to the DispatchSource backend.
    case automatic

    /// Watch every directory with one `DispatchSourceFileSystemObject`.
    ///
    /// This preserves the original FSWatcher behavior and follows symlinked
    /// directories when requested, but large trees consume one file descriptor
    /// per watched directory.
    case dispatchSource

    /// Watch the root hierarchy with one macOS FSEvents stream.
    ///
    /// This backend is macOS-only and does not follow symlinked directories as
    /// independent recursive roots.
    case fsevents
}

/// Options for recursive directory watching
public struct RecursiveWatchOptions {
    /// Maximum depth to watch (nil for unlimited)
    public var maxDepth: Int?

    /// Whether to follow symbolic links
    public var followSymlinks: Bool = false

    /// Glob patterns to exclude (e.g., "*.tmp", "node_modules")
    public var excludePatterns: [String] = []

    /// Hard ceiling on the number of subdirectories the recursive watcher will
    /// open at once. Each watched directory holds an `O_EVTONLY` file
    /// descriptor; on sandboxed macOS apps the per-process FD limit is around
    /// 256, so the default keeps headroom for the rest of the app.
    /// When the ceiling is hit further subdirectories are silently skipped and
    /// `onError(.tooManyWatchers(limit:))` is emitted once.
    public var maxWatchedDirectories: Int = 256

    /// Recursive watching implementation.
    ///
    /// Defaults to `.dispatchSource` to preserve FSWatcher 0.1.x behavior.
    /// Use `.fsevents` or `.automatic` for large macOS directory trees.
    public var backend: RecursiveWatchBackend = .dispatchSource

    /// Initialize with default options
    public init() {}

    /// Initialize with custom options
    /// - Parameters:
    ///   - maxDepth: Maximum depth to watch
    ///   - followSymlinks: Whether to follow symbolic links
    ///   - excludePatterns: Patterns to exclude
    ///   - maxWatchedDirectories: Hard ceiling on simultaneously watched directories
    ///   - backend: Recursive watching implementation
    public init(
        maxDepth: Int? = nil,
        followSymlinks: Bool = false,
        excludePatterns: [String] = [],
        maxWatchedDirectories: Int = 256
    ) {
        self.maxDepth = maxDepth
        self.followSymlinks = followSymlinks
        self.excludePatterns = excludePatterns
        self.maxWatchedDirectories = maxWatchedDirectories
        self.backend = .dispatchSource
    }

    /// Initialize with custom options and backend selection.
    /// - Parameters:
    ///   - maxDepth: Maximum depth to watch
    ///   - followSymlinks: Whether to follow symbolic links
    ///   - excludePatterns: Patterns to exclude
    ///   - maxWatchedDirectories: Hard ceiling on simultaneously watched directories
    ///   - backend: Recursive watching implementation
    public init(
        maxDepth: Int? = nil,
        followSymlinks: Bool = false,
        excludePatterns: [String] = [],
        maxWatchedDirectories: Int = 256,
        backend: RecursiveWatchBackend
    ) {
        self.maxDepth = maxDepth
        self.followSymlinks = followSymlinks
        self.excludePatterns = excludePatterns
        self.maxWatchedDirectories = maxWatchedDirectories
        self.backend = backend
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

    #if os(macOS)
        private var eventStream: FSEventStreamRef?
        private var fseventsIsWatching = false
        private let fseventsLock = NSLock()
        private var fseventsPendingDirectories: Set<URL> = []
        private var fseventsPendingFileEvents: [URL: FileSystemEvent] = [:]
        private var fseventsDebounceWorkItem: DispatchWorkItem?
        private let fseventsPendingLock = NSLock()
    #endif

    /// Set once when `maxWatchedDirectories` is hit, so the limit is reported
    /// to `onError` exactly once per recursive scan instead of spamming.
    private var tooManyWatchersReported = false
    private let tooManyWatchersLock = NSLock()

    // Event handlers
    public weak var delegate: DirectoryWatcherDelegate?
    public var onDirectoryChange: ((URL) -> Void)?
    public var onFilteredChange: (([URL]) -> Void)?
    public var onFileChange: ((FileSystemEvent) -> Void)?
    public var onError: ((FSWatcherError) -> Void)?

    // Combine support
    private let directoryChangeSubject = PassthroughSubject<URL, Never>()
    private let filteredChangeSubject = PassthroughSubject<[URL], Never>()
    private let fileChangeSubject = PassthroughSubject<FileSystemEvent, Never>()

    // Swift Concurrency support
    private var continuations: [UUID: AsyncStream<URL>.Continuation] = [:]
    private var filteredContinuations: [UUID: AsyncStream<[URL]>.Continuation] = [:]
    private var fileContinuations: [UUID: AsyncStream<FileSystemEvent>.Continuation] = [:]
    private let continuationLock = NSLock()

    // MARK: - Initialization

    /// Initialize a recursive directory watcher
    /// - Parameters:
    ///   - url: The root directory to watch
    ///   - options: Options for recursive watching
    ///   - configuration: Configuration for individual watchers
    /// - Throws: FSWatcherError if initialization fails
    public init(
        url: URL, options: RecursiveWatchOptions = RecursiveWatchOptions(),
        configuration: DirectoryWatcher.Configuration = DirectoryWatcher.Configuration()
    ) throws {
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

    /// Start watching the directory recursively (synchronous).
    ///
    /// On large or cloud-synced trees the initial scan can take seconds and
    /// will block the calling thread. On the main thread that puts the app at
    /// risk of the macOS launch watchdog. Prefer `start(on:)` for app-launch
    /// paths.
    public func start() {
        resetLimitReporting()
        switch resolveBackendForStart() {
        case .dispatchSource:
            scanAndWatchSubdirectories(at: rootURL, currentDepth: 0)
        case .fsevents:
            startFSEvents()
        case .automatic:
            break
        }
    }

    /// Start watching asynchronously on the given dispatch queue.
    ///
    /// The recursive scan and per-directory `open(O_EVTONLY)` calls run on
    /// `queue` instead of the caller's thread, so this is safe to invoke from
    /// the main thread during app launch. Event delivery still goes through
    /// the queue configured on `DirectoryWatcher.Configuration`.
    /// - Parameter queue: Background queue to perform the scan on. Defaults
    ///   to a utility-priority global queue.
    public func start(on queue: DispatchQueue = .global(qos: .utility)) {
        resetLimitReporting()
        let backend = resolveBackendForStart()
        queue.async { [weak self] in
            guard let self = self else { return }
            switch backend {
            case .dispatchSource:
                self.scanAndWatchSubdirectories(at: self.rootURL, currentDepth: 0)
            case .fsevents:
                self.startFSEvents()
            case .automatic:
                break
            }
        }
    }

    /// Async/await variant of `start(on:)`. Returns once the initial recursive
    /// scan has completed.
    public func startAsync(on queue: DispatchQueue = .global(qos: .utility)) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            resetLimitReporting()
            let backend = resolveBackendForStart()
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                switch backend {
                case .dispatchSource:
                    self.scanAndWatchSubdirectories(at: self.rootURL, currentDepth: 0)
                case .fsevents:
                    self.startFSEvents()
                case .automatic:
                    break
                }
                continuation.resume()
            }
        }
    }

    private func resolveBackendForStart() -> RecursiveWatchBackend {
        switch options.backend {
        case .automatic:
            #if os(macOS)
                return options.followSymlinks ? .dispatchSource : .fsevents
            #else
                return .dispatchSource
            #endif
        case .dispatchSource:
            return .dispatchSource
        case .fsevents:
            #if os(macOS)
                return .fsevents
            #else
                onError?(
                    .invalidConfiguration("FSEvents backend is only available on macOS; using DispatchSource instead."))
                return .dispatchSource
            #endif
        }
    }

    private func resetLimitReporting() {
        tooManyWatchersLock.lock()
        tooManyWatchersReported = false
        tooManyWatchersLock.unlock()
    }

    /// Stop watching all directories
    public func stop() {
        stopFSEvents()

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
        fileContinuations.values.forEach { $0.finish() }
        fileContinuations.removeAll()
        continuationLock.unlock()
    }

    /// Check if the watcher is currently watching
    public var isWatching: Bool {
        #if os(macOS)
            fseventsLock.lock()
            let isWatchingFSEvents = fseventsIsWatching
            fseventsLock.unlock()
            if isWatchingFSEvents {
                return true
            }
        #endif

        watchersLock.lock()
        defer { watchersLock.unlock() }
        return !watchers.isEmpty && watchers.values.contains { $0.isWatching }
    }

    /// Get all watched directories
    public var watchedDirectories: [URL] {
        #if os(macOS)
            fseventsLock.lock()
            let isWatchingFSEvents = fseventsIsWatching
            fseventsLock.unlock()
            if isWatchingFSEvents {
                return [rootURL]
            }
        #endif

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

    /// Publisher for file-level change events.
    public var fileChangePublisher: AnyPublisher<FileSystemEvent, Never> {
        fileChangeSubject.eraseToAnyPublisher()
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

    /// Async stream of file-level changes.
    public var fileChanges: AsyncStream<FileSystemEvent> {
        AsyncStream { continuation in
            let id = UUID()

            continuationLock.lock()
            fileContinuations[id] = continuation
            continuationLock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.continuationLock.lock()
                self?.fileContinuations.removeValue(forKey: id)
                self?.continuationLock.unlock()
            }
        }
    }

    // MARK: - Private Methods

    /// Iterative recursive scan. Uses an explicit stack instead of true
    /// recursion so deep trees cannot blow the call stack, and so that hitting
    /// the `maxWatchedDirectories` ceiling can short-circuit cleanly.
    private func scanAndWatchSubdirectories(at url: URL, currentDepth: Int) {
        var stack: [(URL, Int)] = [(url, currentDepth)]
        while let (currentURL, depth) = stack.popLast() {
            // Check depth limit
            if let maxDepth = options.maxDepth, depth > maxDepth {
                continue
            }

            // Check if directory should be excluded
            let directoryName = currentURL.lastPathComponent
            var excluded = false
            for pattern in options.excludePatterns where matchesGlobPattern(name: directoryName, pattern: pattern) {
                excluded = true
                break
            }
            if excluded { continue }

            // Try to start watching this directory. If we hit the FD ceiling,
            // stop descending entirely — there is no point queueing more work
            // we cannot service.
            let outcome = watchDirectory(currentURL)
            switch outcome {
            case .limitReached:
                return
            case .alreadyWatching, .started, .failed:
                break
            }

            // Scan subdirectories
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: currentURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )

                for item in contents {
                    var isDirectory: ObjCBool = false
                    var isSymlink = false

                    // Check if it's a symbolic link
                    if let resourceValues = try? item.resourceValues(forKeys: [.isSymbolicLinkKey]),
                        let isSymbolicLink = resourceValues.isSymbolicLink
                    {
                        isSymlink = isSymbolicLink
                    }

                    // Skip symlinks if not following them
                    if isSymlink && !options.followSymlinks {
                        continue
                    }

                    // Check if it's a directory
                    if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                        isDirectory.boolValue
                    {
                        stack.append((item, depth + 1))
                    }
                }
            } catch {
                // Ignore errors for individual directories
            }
        }
    }

    private enum WatchOutcome {
        case alreadyWatching
        case started
        case limitReached
        case failed
    }

    private func watchDirectory(_ url: URL) -> WatchOutcome {
        watchersLock.lock()

        // Check if already watching
        if watchers[url] != nil {
            watchersLock.unlock()
            return .alreadyWatching
        }

        // Enforce the configured ceiling on simultaneously watched
        // directories. Each watcher holds an O_EVTONLY file descriptor; on a
        // sandboxed app the per-process FD limit is small (~256) and a deep
        // cloud-synced tree can blow past it, after which every subsequent
        // open() fails. Stopping early is much friendlier than letting FDs
        // exhaust silently.
        if watchers.count >= options.maxWatchedDirectories {
            let limit = options.maxWatchedDirectories
            watchersLock.unlock()

            tooManyWatchersLock.lock()
            let alreadyReported = tooManyWatchersReported
            tooManyWatchersReported = true
            tooManyWatchersLock.unlock()

            if !alreadyReported {
                onError?(.tooManyWatchers(limit: limit))
            }
            return .limitReached
        }

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
            watchersLock.unlock()
            return .started
        } catch {
            watchersLock.unlock()
            // Surface the failure so callers can log/observe instead of
            // having errors disappear into the void.
            if let fsError = error as? FSWatcherError {
                onError?(fsError)
            } else {
                onError?(.failedToWatch(url, underlying: error))
            }
            return .failed
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
                    isDirectory.boolValue
                {

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
        var regexPattern =
            pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        // Anchor the pattern
        regexPattern = "^" + regexPattern + "$"

        return name.range(of: regexPattern, options: .regularExpression) != nil
    }

    #if os(macOS)
        private func startFSEvents() {
            if options.followSymlinks {
                onError?(
                    .invalidConfiguration(
                        "FSEvents backend does not follow symlinked directories; use .automatic or .dispatchSource when followSymlinks is true."
                    ))
            }

            fseventsLock.lock()
            guard eventStream == nil else {
                fseventsLock.unlock()
                return
            }
            fseventsLock.unlock()

            var context = FSEventStreamContext(
                version: 0,
                info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let flags =
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
                | FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
                | FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
                | FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
            let latency = max(0.05, min(configuration.debounceInterval, 1.0))

            guard
                let stream = FSEventStreamCreate(
                    kCFAllocatorDefault,
                    Self.fseventsCallback,
                    &context,
                    [rootURL.standardizedFileURL.path] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    latency,
                    flags
                )
            else {
                onError?(.systemResourcesUnavailable)
                return
            }

            FSEventStreamSetDispatchQueue(stream, configuration.queue)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                onError?(.failedToWatch(rootURL, underlying: FSWatcherError.systemResourcesUnavailable))
                return
            }

            fseventsLock.lock()
            eventStream = stream
            fseventsIsWatching = true
            fseventsLock.unlock()
        }

        private func stopFSEvents() {
            fseventsPendingLock.lock()
            fseventsDebounceWorkItem?.cancel()
            fseventsDebounceWorkItem = nil
            fseventsPendingDirectories.removeAll()
            fseventsPendingFileEvents.removeAll()
            fseventsPendingLock.unlock()

            fseventsLock.lock()
            let stream = eventStream
            eventStream = nil
            fseventsIsWatching = false
            fseventsLock.unlock()

            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }

        private static let fseventsCallback: FSEventStreamCallback = { _, info, count, paths, flags, eventIds in
            guard let info else { return }
            let watcher = Unmanaged<RecursiveDirectoryWatcher>
                .fromOpaque(info)
                .takeUnretainedValue()
            let eventPaths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handleFSEvents(paths: eventPaths, flags: flags, eventIds: eventIds, count: count)
        }

        private func handleFSEvents(
            paths: [String],
            flags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>,
            count: Int
        ) {
            var changedDirectories: Set<URL> = []
            var fileEvents: [FileSystemEvent] = []

            for index in 0..<min(paths.count, count) {
                let eventFlags = flags[index]
                guard shouldProcessFSEvent(eventFlags) else { continue }

                let event = fileSystemEvent(
                    forFSEventPath: paths[index],
                    flags: eventFlags,
                    eventID: UInt64(eventIds[index])
                )
                let depthURL = event.itemKind == .file ? event.url.deletingLastPathComponent() : event.url
                guard
                    isWithinRoot(depthURL),
                    isWithinDepth(depthURL),
                    !isExcluded(event.url)
                else {
                    continue
                }

                if event.itemKind == .file {
                    fileEvents.append(event)
                    changedDirectories.insert(event.url.deletingLastPathComponent().standardizedFileURL)
                } else {
                    changedDirectories.insert(directoryURL(for: event))
                }
            }

            guard !changedDirectories.isEmpty || !fileEvents.isEmpty else { return }
            enqueueFSEvents(changedDirectories, fileEvents: fileEvents)
        }

        private func shouldProcessFSEvent(_ flags: FSEventStreamEventFlags) -> Bool {
            let ignoredFlags =
                FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagMount)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount)

            return flags & ignoredFlags == 0
        }

        private func directoryURL(forFSEventPath path: String, flags: FSEventStreamEventFlags) -> URL {
            if requiresFullRescan(flags) {
                return rootURL.standardizedFileURL
            }

            let url = URL(fileURLWithPath: path).standardizedFileURL
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return url
                }
                return url.deletingLastPathComponent().standardizedFileURL
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
            return url.deletingLastPathComponent().standardizedFileURL
        }

        private func directoryURL(for event: FileSystemEvent) -> URL {
            if event.requiresRescan {
                return rootURL.standardizedFileURL
            }
            if event.itemKind == .directory {
                return event.url.standardizedFileURL
            }
            return event.url.deletingLastPathComponent().standardizedFileURL
        }

        private func fileSystemEvent(
            forFSEventPath path: String,
            flags: FSEventStreamEventFlags,
            eventID: UInt64
        ) -> FileSystemEvent {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let itemKind = itemKind(for: url, flags: flags)
            return FileSystemEvent(
                url: url,
                eventType: eventType(for: flags),
                itemKind: itemKind,
                requiresRescan: requiresFullRescan(flags),
                rawFlags: UInt32(flags),
                eventID: eventID
            )
        }

        private func itemKind(for url: URL, flags: FSEventStreamEventFlags) -> FileSystemEvent.ItemKind {
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 {
                return .file
            }
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 {
                return .directory
            }
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsSymlink) != 0 {
                return .symbolicLink
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .unknown
            }
            return isDirectory.boolValue ? .directory : .file
        }

        private func eventType(for flags: FSEventStreamEventFlags) -> FileSystemEvent.EventType {
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
                return .created
            }
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
                return .deleted
            }
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
                return .renamed
            }
            let modifiedFlags =
                FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod)
            if flags & modifiedFlags != 0 {
                return .modified
            }
            return .unknown
        }

        private func requiresFullRescan(_ flags: FSEventStreamEventFlags) -> Bool {
            let rescanFlags =
                FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
                | FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)

            return flags & rescanFlags != 0
        }

        private func isWithinRoot(_ url: URL) -> Bool {
            let rootPath = canonicalPath(rootURL)
            let path = canonicalPath(url)
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }

        private func isWithinDepth(_ url: URL) -> Bool {
            guard let maxDepth = options.maxDepth else { return true }
            return fseventsDepth(for: url) <= maxDepth
        }

        private func isExcluded(_ url: URL) -> Bool {
            guard !options.excludePatterns.isEmpty else { return false }
            let rootComponents = canonicalPath(rootURL).split(separator: "/")
            let components = canonicalPath(url).split(separator: "/")
            guard components.count >= rootComponents.count else { return false }

            let relativeComponents = components.dropFirst(rootComponents.count)
            for component in relativeComponents {
                for pattern in options.excludePatterns
                where matchesGlobPattern(name: String(component), pattern: pattern) {
                    return true
                }
            }
            return false
        }

        private func fseventsDepth(for url: URL) -> Int {
            let rootPath = canonicalPath(rootURL)
            let path = canonicalPath(url)
            guard path != rootPath else { return 0 }
            let relativePath = path.dropFirst(rootPath.count).drop { $0 == "/" }
            return relativePath.split(separator: "/").count
        }

        private func canonicalPath(_ url: URL) -> String {
            url.resolvingSymlinksInPath().standardizedFileURL.path
        }

        private func enqueueFSEvents(_ directories: Set<URL>, fileEvents: [FileSystemEvent]) {
            fseventsPendingLock.lock()
            fseventsPendingDirectories.formUnion(directories)
            for event in fileEvents {
                fseventsPendingFileEvents[event.url] = event
            }
            fseventsDebounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.flushFSEvents()
            }
            fseventsDebounceWorkItem = workItem
            fseventsPendingLock.unlock()

            configuration.queue.asyncAfter(deadline: .now() + configuration.debounceInterval, execute: workItem)
        }

        private func flushFSEvents() {
            fseventsPendingLock.lock()
            let directories = fseventsPendingDirectories
            let fileEvents = Array(fseventsPendingFileEvents.values)
            fseventsPendingDirectories.removeAll()
            fseventsPendingFileEvents.removeAll()
            fseventsDebounceWorkItem = nil
            fseventsPendingLock.unlock()

            let sortedFileEvents = fileEvents.sorted { $0.url.path < $1.url.path }
            var filteredFiles: [URL] = []
            for event in sortedFileEvents {
                handleFileChange(event)
                if shouldEmitFilteredFileEvent(event) {
                    filteredFiles.append(event.url)
                }
            }
            if !filteredFiles.isEmpty {
                handleFilteredChange(filteredFiles)
            }

            for directory in directories.sorted(by: { $0.path < $1.path }) {
                handleDirectoryChange(directory)
                if shouldScanDirectoryEvent(directory, fileEvents: sortedFileEvents) {
                    let filteredFiles = getFilteredFilesRecursively(in: directory)
                    if !filteredFiles.isEmpty {
                        handleFilteredChange(filteredFiles)
                    }
                }
            }
        }

        private func shouldEmitFilteredFileEvent(_ event: FileSystemEvent) -> Bool {
            guard event.itemKind == .file else { return false }
            guard event.eventType != .deleted else { return false }
            guard FileManager.default.fileExists(atPath: event.url.path) else { return false }
            guard !isHidden(event.url) else { return false }
            if configuration.ignoreList.shouldIgnore(event.url) {
                return false
            }
            if !configuration.filterChain.isEmpty && !configuration.filterChain.matches(event.url) {
                return false
            }
            return true
        }

        private func shouldScanDirectoryEvent(_ directory: URL, fileEvents: [FileSystemEvent]) -> Bool {
            guard configuration.scansChangedDirectoriesForFilteredEvents else {
                return false
            }
            if fileEvents.contains(where: { $0.requiresRescan }) {
                return true
            }
            if !fileEvents.isEmpty,
                fileEvents.allSatisfy({
                    $0.itemKind == .file && $0.url.deletingLastPathComponent().standardizedFileURL == directory
                })
            {
                return false
            }
            if directory == rootURL.standardizedFileURL {
                return true
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                return false
            }
            return !fileEvents.contains { event in
                event.itemKind == .file && event.url.deletingLastPathComponent().standardizedFileURL == directory
            }
        }

        private func isHidden(_ url: URL) -> Bool {
            if url.lastPathComponent.hasPrefix(".") {
                return true
            }
            return (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
        }
        private func getFilteredFilesRecursively(in directory: URL) -> [URL] {
            let depth = fseventsDepth(for: directory)
            let remainingDepth = options.maxDepth.map { max(0, $0 - depth) }
            return getFilteredFiles(in: directory, maxDepth: remainingDepth, currentDepth: 0)
        }

        private func getFilteredFiles(in directory: URL, maxDepth: Int?, currentDepth: Int) -> [URL] {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                var filteredFiles: [URL] = []
                for fileURL in contents {
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                        continue
                    }

                    if isDirectory.boolValue {
                        guard !isExcluded(fileURL) else { continue }
                        if maxDepth == nil || currentDepth < (maxDepth ?? 0) {
                            filteredFiles.append(
                                contentsOf: getFilteredFiles(
                                    in: fileURL, maxDepth: maxDepth, currentDepth: currentDepth + 1))
                        }
                        continue
                    }

                    if configuration.ignoreList.shouldIgnore(fileURL) {
                        continue
                    }

                    if !configuration.filterChain.isEmpty && !configuration.filterChain.matches(fileURL) {
                        continue
                    }

                    filteredFiles.append(fileURL)
                }
                return filteredFiles
            } catch {
                return []
            }
        }
    #else
        private func startFSEvents() {
            onError?(.invalidConfiguration("FSEvents backend is only available on macOS."))
        }

        private func stopFSEvents() {}
    #endif

    private func handleDirectoryChange(_ url: URL) {
        // Create event
        let event = FileSystemEvent(url: url, eventType: .modified, itemKind: .directory)

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

    private func handleFileChange(_ event: FileSystemEvent) {
        delegate?.fileDidChange(with: event)

        onFileChange?(event)

        fileChangeSubject.send(event)

        continuationLock.lock()
        fileContinuations.values.forEach { $0.yield(event) }
        continuationLock.unlock()
    }

    private func handleFilteredChange(_ urls: [URL]) {
        if let predictor = configuration.transformPredictor {
            for file in urls {
                let predictedOutputs = predictor.predictOutputFiles(for: file)
                if !predictedOutputs.isEmpty {
                    configuration.ignoreList.addPredictiveIgnore(predictedOutputs)
                }
            }
        }

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
