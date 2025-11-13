# FSWatcher API Documentation

## Core Classes

### DirectoryWatcher

The main class for monitoring changes in a single directory.

#### Initialization

```swift
public init(url: URL, configuration: Configuration = Configuration()) throws
```

**Parameters:**

- `url`: The directory URL to watch
- `configuration`: Configuration options for the watcher

**Throws:** `FSWatcherError` if initialization fails

#### Properties

```swift
// Event handlers
public weak var delegate: DirectoryWatcherDelegate?
public var onDirectoryChange: ((URL) -> Void)?
public var onFilteredChange: (([URL]) -> Void)?
public var onError: ((FSWatcherError) -> Void)?

// Combine support
public var directoryChangePublisher: AnyPublisher<URL, Never> { get }
public var filteredChangePublisher: AnyPublisher<[URL], Never> { get }

// Swift Concurrency support  
public var directoryChanges: AsyncStream<URL> { get }
public var filteredChanges: AsyncStream<[URL]> { get }

// State
public var isWatching: Bool { get }
```

#### Methods

```swift
public func start()
public func stop()
public func addFilter(_ filter: FileFilter)
public func clearFilters()
public func addIgnoredFiles(_ urls: [URL])
public func addPredictiveIgnore(_ urls: [URL])
```

### MultiDirectoryWatcher

Manages monitoring of multiple directories simultaneously.

#### MultiDirectoryWatcher - Initialization

```swift
public init(configuration: DirectoryWatcher.Configuration = DirectoryWatcher.Configuration())
```

#### MultiDirectoryWatcher - Methods

```swift
public func startWatching(directories: [URL])
public func startWatching(directory: URL)
public func stopWatching(directory: URL)
public func stopAllWatching()
public func isWatching(directory: URL) -> Bool

// Properties
public var watchedDirectories: [URL] { get }
public var isWatching: Bool { get }
```

### RecursiveDirectoryWatcher

Monitors directories and their subdirectories recursively.

#### RecursiveDirectoryWatcher - Initialization

```swift
public init(url: URL, options: RecursiveWatchOptions = RecursiveWatchOptions(), configuration: DirectoryWatcher.Configuration = DirectoryWatcher.Configuration()) throws
```

#### RecursiveWatchOptions

```swift
public struct RecursiveWatchOptions {
    public var maxDepth: Int? = nil
    public var followSymlinks: Bool = false
    public var excludePatterns: [String] = []
    
    public init()
    public init(maxDepth: Int? = nil, followSymlinks: Bool = false, excludePatterns: [String] = [])
}
```

### MultiRecursiveDirectoryWatcher

Manages recursive monitoring of multiple directories simultaneously.

#### MultiRecursiveDirectoryWatcher - Initialization

```swift
public init(options: RecursiveWatchOptions = RecursiveWatchOptions(), configuration: DirectoryWatcher.Configuration = DirectoryWatcher.Configuration())
```

#### MultiRecursiveDirectoryWatcher - Methods

```swift
public func startWatching(directories: [URL])
public func startWatching(directory: URL)
public func stopWatching(directory: URL)
public func stopAllWatching()
public func isWatching(directory: URL) -> Bool

// Filter management
public func addFilter(_ filter: FileFilter)
public func addFilter(_ filter: FileFilter, to directory: URL)
public func clearAllFilters()

// Ignore list management
public func addIgnoredFiles(_ urls: [URL])
public func addIgnoredFiles(_ urls: [URL], in directory: URL)
public func addPredictiveIgnore(_ urls: [URL])
public func addPredictiveIgnore(_ urls: [URL], in directory: URL)

// Properties
public var watchedDirectories: [URL] { get }
public var allWatchedDirectories: [URL] { get }
public var isWatching: Bool { get }
```

## Configuration

### DirectoryWatcher.Configuration

```swift
public struct Configuration {
    public var debounceInterval: TimeInterval = 0.5
    public var eventMask: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename]
    public var queue: DispatchQueue = .global(qos: .utility)
    public var filterChain: FilterChain = FilterChain()
    public var ignoreList: IgnoreList = IgnoreList()
    public var transformPredictor: FileTransformPredictor?
    
    public init()
}
```

## Filtering System

### FileFilter

```swift
public struct FileFilter {
    // Predefined filters
    public static func fileExtensions(_ extensions: [String]) -> FileFilter
    public static func utTypes(_ types: [UTType]) -> FileFilter
    public static func fileName(matching pattern: String) -> FileFilter
    public static func fileSize(_ range: ClosedRange<Int>) -> FileFilter
    public static func modifiedWithin(_ interval: TimeInterval) -> FileFilter
    public static func custom(_ predicate: @escaping (URL) -> Bool) -> FileFilter
    
    // Convenience filters
    public static var imageFiles: FileFilter
    public static var videoFiles: FileFilter
    public static var audioFiles: FileFilter
    public static var documentFiles: FileFilter
    public static var directoriesOnly: FileFilter
    public static var filesOnly: FileFilter
    
    // Combinators
    public func and(_ other: FileFilter) -> FileFilter
    public func or(_ other: FileFilter) -> FileFilter
    public func not() -> FileFilter
}
```

### FilterChain

```swift
public struct FilterChain {
    public init()
    public init(filters: [FileFilter])
    
    public mutating func add(_ filter: FileFilter)
    public mutating func clear()
    
    public var isEmpty: Bool { get }
    public var count: Int { get }
    
    public func matches(_ url: URL) -> Bool
    public func matchesAny(_ url: URL) -> Bool
    public func filter(_ urls: [URL]) -> [URL]
    public func filterAny(_ urls: [URL]) -> [URL]
}
```

## Ignore System

### IgnoreList

```swift
public class IgnoreList {
    public init()
    public init(ignoredFiles: [URL])
    
    // Managing ignored files
    public func addIgnored(_ urls: [URL])
    public func addIgnored(_ url: URL)
    public func removeIgnored(_ urls: [URL])
    public func removeIgnored(_ url: URL)
    
    // Predictive ignoring
    public func addPredictiveIgnore(_ urls: [URL])
    public func addPredictiveIgnore(_ url: URL)
    public func removePredictiveIgnore(_ urls: [URL])
    
    // Pattern-based ignoring
    public func addIgnorePattern(_ pattern: String)
    public func addIgnorePatterns(_ patterns: [String])
    public func removeIgnorePattern(_ pattern: String)
    
    // Checking ignore status
    public func shouldIgnore(_ url: URL) -> Bool
    
    // Maintenance
    public func cleanup()
    public func clear()
    public func clearIgnored()
    public func clearPredictive()
    public func clearPatterns()
    
    // Properties
    public var ignoredCount: Int { get }
    public var predictiveCount: Int { get }
    public var patternCount: Int { get }
}
```

### FileTransformPredictor

```swift
public struct FileTransformPredictor {
    public struct TransformRule {
        public let inputPattern: String
        public let outputTemplate: String
        public let formatChange: Bool
        
        public init(inputPattern: String, outputTemplate: String, formatChange: Bool = false)
    }
    
    public init(rules: [TransformRule])
    public init(rule: TransformRule)
    
    public func predictOutputFiles(for inputURL: URL) -> [URL]
    public func predictOutputFiles(for inputURLs: [URL]) -> [URL]
    
    // Factory methods
    public static func imageCompression(suffix: String = "_compressed") -> FileTransformPredictor
    public static func formatConversion(from: String, to: String) -> FileTransformPredictor
    public static func thumbnailGeneration(prefix: String = "thumb_", size: String = "") -> FileTransformPredictor
    public static func videoTranscoding(outputFormat: String = "mp4") -> FileTransformPredictor
    public static func documentConversion() -> FileTransformPredictor
}
```

## Events and Protocols

### FileSystemEvent

```swift
public struct FileSystemEvent {
    public let url: URL
    public let eventType: EventType
    public let timestamp: Date
    
    public enum EventType {
        case created
        case modified
        case deleted
        case renamed
        case unknown
    }
    
    public init(url: URL, eventType: EventType, timestamp: Date = Date())
}
```

### DirectoryWatcherDelegate

```swift
public protocol DirectoryWatcherDelegate: AnyObject {
    func directoryDidChange(at url: URL)
    func directoryDidChange(with event: FileSystemEvent)
}
```

## Error Handling

### FSWatcherError

```swift
public enum FSWatcherError: Error, LocalizedError {
    case cannotOpenDirectory(URL)
    case insufficientPermissions(URL)
    case directoryNotFound(URL)
    case systemResourcesUnavailable
    case invalidConfiguration(String)
    
    public var errorDescription: String? { get }
}
```

## Extensions

### URL+Extensions

```swift
extension URL {
    public var isDirectory: Bool { get }
    public var isRegularFile: Bool { get }
    public var fileExists: Bool { get }
    public var fileSize: Int? { get }
    public var modificationDate: Date? { get }
    public var creationDate: Date? { get }
    public var isSymbolicLink: Bool { get }
    public var isHidden: Bool { get }
    
    public func subdirectories(includingHidden: Bool = false) -> [URL]
    public func files(includingHidden: Bool = false) -> [URL]
    public func contents(includingHidden: Bool = false) -> [URL]
}
```

## Usage Patterns

### Basic Usage

```swift
let watcher = try DirectoryWatcher(url: directoryURL)
watcher.onDirectoryChange = { url in
    print("Directory changed: \(url)")
}
watcher.start()
```

### With Filters

```swift
var config = DirectoryWatcher.Configuration()
config.filterChain.add(.imageFiles)
config.filterChain.add(.fileSize(1024...))

let watcher = try DirectoryWatcher(url: directoryURL, configuration: config)
watcher.onFilteredChange = { files in
    print("Filtered files: \(files)")
}
```

### With Combine

```swift
watcher.directoryChangePublisher
    .debounce(for: .seconds(1), scheduler: RunLoop.main)
    .sink { url in
        print("Debounced change: \(url)")
    }
    .store(in: &cancellables)
```

### With Swift Concurrency

```swift
Task {
    for await url in watcher.directoryChanges {
        await processChange(at: url)
    }
}
```
