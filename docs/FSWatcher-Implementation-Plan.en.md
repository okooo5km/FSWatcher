# FSWatcher Swift Package Implementation Plan

## Overview

Based on the successful file system monitoring functionality implemented in the Zipic project, we plan to extract it into an independent, efficient, and reusable Swift Package. This package uses native `DispatchSource` APIs to implement low CPU usage file system event monitoring, providing significant performance improvements compared to traditional polling approaches.

## Current Implementation Analysis

### Technical Features

1. **Event-Driven Architecture**: Uses `DispatchSource.makeFileSystemObjectSource` to listen for file system events
2. **Low Resource Usage**: Avoids timer polling, only triggers when file system events occur
3. **Debounce Mechanism**: Uses 0.5-second debounce interval to avoid frequent triggering
4. **Multi-Directory Support**: Can monitor multiple directories simultaneously
5. **Delegate Pattern**: Uses delegate pattern for event delivery

### Core Components

- `DirectoryWatcher`: Single directory monitor
- `MultiDirectoryWatcher`: Multi-directory monitoring manager
- `DirectoryWatcherDelegate`: Event notification protocol

## Swift Package Design

### 1. Package Information

```plaintext
Package Name: FSWatcher
Swift Tools Version: 5.9
Platforms: macOS 12.0+, iOS 15.0+
```

### 2. Directory Structure

```bash
FSWatcher/
├── Package.swift
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── Sources/
│   ├── FSWatcher/
│   │   ├── Core/
│   │   │   ├── DirectoryWatcher.swift
│   │   │   ├── MultiDirectoryWatcher.swift
│   │   │   └── FileSystemEvent.swift
│   │   ├── Filters/
│   │   │   ├── FileFilter.swift
│   │   │   └── FilterChain.swift
│   │   ├── IgnoreList/
│   │   │   ├── IgnoreList.swift
│   │   │   └── FileTransformPredictor.swift
│   │   ├── Recursive/
│   │   │   └── RecursiveDirectoryWatcher.swift
│   │   ├── Protocols/
│   │   │   └── DirectoryWatcherDelegate.swift
│   │   ├── Extensions/
│   │   │   └── URL+Extensions.swift
│   │   └── Utils/
│   │       ├── DebounceTimer.swift
│   │       └── FSWatcherError.swift
│   └── FSWatcherExample/
│       └── main.swift
├── Tests/
│   └── FSWatcherTests/
│       ├── DirectoryWatcherTests.swift
│       ├── FilterTests.swift
│       └── IgnoreListTests.swift
├── Examples/
│   ├── BasicUsage.swift
│   └── ImageCompression.swift
└── docs/
    ├── API.md
    ├── Advanced.md
    ├── Migration.md
    ├── Performance.md
    └── FSWatcher-Implementation-Plan.en.md
```

### 3. Core API Design

#### 3.1 FileSystemEvent

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
}
```

#### 3.2 DirectoryWatcher

```swift
public class DirectoryWatcher {
    public struct Configuration {
        public var debounceInterval: TimeInterval = 0.5
        public var eventMask: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename]
        public var queue: DispatchQueue = .global(qos: .utility)
        public var filterChain: FilterChain = FilterChain()
        public var ignoreList: IgnoreList = IgnoreList()
        public var transformPredictor: FileTransformPredictor? = nil
        
        public init() {}
    }
    
    public init(url: URL, configuration: Configuration = Configuration()) throws
    
    // Delegate pattern
    public weak var delegate: DirectoryWatcherDelegate?
    
    // Closure pattern
    public var onDirectoryChange: ((URL) -> Void)?
    public var onFilteredChange: (([URL]) -> Void)?
    
    // Combine support
    public var directoryChangePublisher: AnyPublisher<URL, Never> { get }
    public var filteredChangePublisher: AnyPublisher<[URL], Never> { get }
    
    // Swift Concurrency support
    public var directoryChanges: AsyncStream<URL> { get }
    public var filteredChanges: AsyncStream<[URL]> { get }
    
    // Filter management
    public func addFilter(_ filter: FileFilter)
    public func clearFilters()
    
    // Ignore list management
    public func addIgnoredFiles(_ urls: [URL])
    public func addPredictiveIgnore(_ urls: [URL])
    
    public func start()
    public func stop()
    public var isWatching: Bool { get }
}
```

### 4. Advanced Features

#### 4.1 Smart Filtering System

```swift
public struct FileFilter {
    // File extension filters
    public static func fileExtensions(_ extensions: [String]) -> FileFilter
    
    // UTType filters (inspired by Zipic's isImageFile implementation)
    public static func utTypes(_ types: [UTType]) -> FileFilter
    
    // Convenience filters
    public static var imageFiles: FileFilter
    public static var videoFiles: FileFilter
    public static var audioFiles: FileFilter
    public static var documentFiles: FileFilter
    
    // Custom filters
    public static func fileName(matching pattern: String) -> FileFilter
    public static func fileSize(_ range: ClosedRange<Int>) -> FileFilter
    public static func modifiedWithin(_ interval: TimeInterval) -> FileFilter
    public static func custom(_ predicate: @escaping (URL) -> Bool) -> FileFilter
    
    // Filter combinators
    public func and(_ other: FileFilter) -> FileFilter
    public func or(_ other: FileFilter) -> FileFilter
    public func not() -> FileFilter
}

public struct FilterChain {
    public init()
    public mutating func add(_ filter: FileFilter)
    public func matches(_ url: URL) -> Bool
    public func filter(_ urls: [URL]) -> [URL]
}
```

#### 4.2 Ignore List Mechanism

```swift
public class IgnoreList {
    // Add processed files to ignore list
    public func addIgnored(_ urls: [URL])
    
    // Predictive ignoring: add files that will be generated before processing
    public func addPredictiveIgnore(_ urls: [URL])
    
    // Pattern-based ignoring
    public func addIgnorePattern(_ pattern: String)
    
    // Check if file should be ignored
    public func shouldIgnore(_ url: URL) -> Bool
    
    // Cleanup expired ignore entries
    public func cleanup()
}

public struct FileTransformPredictor {
    public struct TransformRule {
        public let inputPattern: String
        public let outputTemplate: String
        public let formatChange: Bool
    }
    
    public init(rules: [TransformRule])
    
    public func predictOutputFiles(for inputURL: URL) -> [URL]
    
    // Factory methods
    public static func imageCompression(suffix: String = "_compressed") -> FileTransformPredictor
    public static func formatConversion(from: String, to: String) -> FileTransformPredictor
    public static func thumbnailGeneration(prefix: String = "thumb_") -> FileTransformPredictor
}
```

#### 4.3 Recursive Monitoring

```swift
public struct RecursiveWatchOptions {
    public var maxDepth: Int? = nil
    public var followSymlinks: Bool = false
    public var excludePatterns: [String] = []
}

public class RecursiveDirectoryWatcher {
    public init(url: URL, options: RecursiveWatchOptions = RecursiveWatchOptions()) throws
    
    // All DirectoryWatcher functionality
    // Plus recursive directory scanning and monitoring
}
```

### 5. Performance Optimizations

#### 5.1 Resource Management

- Use `deinit` to ensure file descriptors are properly closed
- Implement reference counting to avoid duplicate monitoring of the same directory
- Support pause/resume functionality to reduce resource usage

#### 5.2 Memory Optimization

- Use `weak` references to avoid retain cycles
- Timely cleanup of unneeded watchers
- Proper queue usage to avoid main thread blocking

### 6. Usage Examples

#### 6.1 Basic Usage

```swift
import FSWatcher

let watcher = try DirectoryWatcher(url: URL(fileURLWithPath: "/Users/user/Documents"))

watcher.onDirectoryChange = { url in
    print("Directory changed: \(url)")
}

watcher.start()
```

#### 6.2 Image Processing Pipeline (Zipic-style)

```swift
// Set up transform predictor (similar to Zipic's format conversion logic)
let predictor = FileTransformPredictor(rules: [
    .init(inputPattern: ".*\\.jpe?g$", outputTemplate: "{name}_compressed.jpg"),
    .init(inputPattern: ".*\\.png$", outputTemplate: "{name}.webp", formatChange: true)
])

var config = DirectoryWatcher.Configuration()
config.filterChain.add(.imageFiles)
config.transformPredictor = predictor

let imageWatcher = try DirectoryWatcher(
    url: URL(fileURLWithPath: "/Users/user/Pictures/ToCompress"),
    configuration: config
)

imageWatcher.onFilteredChange = { newImages in
    for imageURL in newImages {
        // Predict output files and add to ignore list
        let predictedOutputs = predictor.predictOutputFiles(for: imageURL)
        imageWatcher.addPredictiveIgnore(predictedOutputs)
        
        // Start compression processing
        compressImage(imageURL) { compressedURL in
            // After compression completion, add actual generated files to ignore list
            imageWatcher.addIgnoredFiles([compressedURL])
        }
    }
}
```

#### 6.3 Development Tool Hot Reload

```swift
var options = RecursiveWatchOptions()
options.excludePatterns = [".git", "node_modules", "*.log", "build"]

let projectWatcher = try RecursiveDirectoryWatcher(url: projectURL, options: options)

// Only monitor source code files
projectWatcher.addFilter(.fileExtensions(["swift", "js", "css", "html"]))

projectWatcher.onFilteredChange = { changedFiles in
    print("Source files changed, triggering build...")
    triggerBuild()
}
```

### 7. Testing Strategy

#### 7.1 Unit Tests

- Test basic monitoring functionality
- Test debounce mechanism
- Test error handling
- Test resource cleanup

#### 7.2 Integration Tests

- Test multi-directory monitoring
- Test concurrent scenarios
- Test long-term stability

### 8. Key Design Principles Learned from Zipic

#### 8.1 Preventive Design

**Inspiration from Zipic's whitelist mechanism**:

- Predict and ignore output files before processing to avoid infinite loops
- This preventive thinking can be applied to other scenarios, such as compilers ignoring generated object files when monitoring source code

#### 8.2 Importance of Smart Filtering

**Learning from `isImageFile` implementation**:

- Use UTType for precise file type determination
- Support unified processing of multiple formats
- Extensible type system design

#### 8.3 Performance-First Architecture Choice

**Advantages of DispatchSource vs Polling**:

- Event-driven is more efficient than timed checking
- System-level integration is more reliable than application-layer polling
- Lower resource usage and more responsive

### 9. Competitive Analysis

| Feature | FSWatcher | fswatch | Watchman | chokidar |
|---------|-----------|---------|----------|----------|
| Language | Pure Swift | C++ | C/Python | JavaScript |
| Platform | Apple Ecosystem | Cross-platform | Cross-platform | Node.js |
| Performance | Native Optimized | High Performance | Facebook Scale | Medium |
| Ease of Use | Swift Friendly | Command Line | Complex Config | JS Ecosystem |
| Modern Features | Combine/Async | None | Partial Support | Promise |
| Filtering | Smart Chaining | Basic | Powerful | Medium |
| Ignore Mechanism | Predictive | Static | Static | Static |

**FSWatcher's Unique Advantages**:

1. **Native Swift Performance**: No bridging overhead
2. **Modern API Design**: Support for latest Swift features
3. **Predictive Ignoring**: Unique mechanism learned from Zipic
4. **Apple Ecosystem Optimization**: Deep integration with macOS/iOS features

## Conclusion

Based on successful implementation and deep analysis of the Zipic project, FSWatcher Swift Package will provide a high-performance, low resource usage, intelligent file system monitoring solution.

**Core Value**:

1. **Event-Driven Architecture**: Efficient monitoring using DispatchSource
2. **Smart Filtering System**: Precise file type identification based on UTType
3. **Predictive Ignoring**: Avoid monitoring self-generated files, preventing infinite loops
4. **Modern Swift Support**: Combine, Swift Concurrency, etc.
5. **Recursive Monitoring**: Configurable depth subdirectory monitoring
6. **Rich Application Scenarios**: From image processing to development tools, from backup systems to content management

This implementation not only solves the technical problems of file system monitoring, but more importantly provides a complete, extensible, modern development practice-compliant solution. By learning from Zipic's successful experience, we can provide Swift developers with a truly practical and efficient file monitoring tool.
