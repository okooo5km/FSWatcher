# Performance Tuning Guide

This guide helps you optimize FSWatcher performance for your specific use case.

## Understanding Performance Characteristics

### Event-Driven vs Polling

FSWatcher uses an event-driven architecture that provides significant performance advantages:

```swift
// ❌ Polling approach (inefficient)
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    // Compare with previous state...
}

// ✅ FSWatcher approach (efficient)
let watcher = try DirectoryWatcher(url: url)
watcher.onDirectoryChange = { changedURL in
    // Only called when actual changes occur
}
```

### Key Performance Metrics

- **CPU Usage**: Minimal when idle, scales with actual file system activity
- **Memory Usage**: ~50KB base + ~1KB per watched directory
- **Latency**: Typically <10ms from file system event to callback
- **Throughput**: Can handle thousands of events per second

## Debouncing Configuration

Debouncing is crucial for performance when dealing with rapid file changes.

### Choosing Debounce Intervals

```swift
var config = DirectoryWatcher.Configuration()

// High-frequency scenarios (log processing, real-time monitoring)
config.debounceInterval = 0.05  // 50ms

// Standard scenarios (development, content management)
config.debounceInterval = 0.5   // 500ms (default)

// Batch processing scenarios
config.debounceInterval = 2.0   // 2 seconds

// Low-priority monitoring
config.debounceInterval = 5.0   // 5 seconds
```

### Dynamic Debouncing

Adjust debouncing based on activity level:

```swift
class AdaptiveWatcher {
    private let watcher: DirectoryWatcher
    private var eventCount = 0
    private var lastEventTime = Date()
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        
        watcher.onDirectoryChange = { [weak self] url in
            self?.adaptDebouncing()
            self?.processChange(url)
        }
    }
    
    private func adaptDebouncing() {
        let now = Date()
        let timeSinceLastEvent = now.timeIntervalSince(lastEventTime)
        
        if timeSinceLastEvent < 1.0 {
            // High frequency - increase debouncing
            watcher.configuration.debounceInterval = min(2.0, watcher.configuration.debounceInterval * 1.5)
        } else if timeSinceLastEvent > 10.0 {
            // Low frequency - decrease debouncing
            watcher.configuration.debounceInterval = max(0.1, watcher.configuration.debounceInterval * 0.8)
        }
        
        lastEventTime = now
    }
}
```

## Filter Optimization

Efficient filtering reduces processing overhead significantly.

### Filter Performance Hierarchy

From fastest to slowest:

1. **Extension filters**: Fast string comparison
2. **Size filters**: Single file system call
3. **UTType filters**: Type system lookup
4. **Modification time filters**: File system metadata access
5. **Custom predicate filters**: Depends on implementation

### Optimized Filter Chains

```swift
// ❌ Inefficient order (expensive filters first)
config.filterChain.add(.custom { url in
    // Complex custom logic...
    return expensiveCheck(url)
})
config.filterChain.add(.fileExtensions(["jpg", "png"]))

// ✅ Efficient order (cheap filters first)
config.filterChain.add(.fileExtensions(["jpg", "png"]))  // Fast elimination
config.filterChain.add(.fileSize(1024...))               // Quick metadata check
config.filterChain.add(.custom { url in                  // Only for remaining files
    return expensiveCheck(url)
})
```

### Precompiled Filters

Cache complex filters:

```swift
class OptimizedWatcher {
    // Precompile expensive filters
    private static let imageFilter = FileFilter.imageFiles
    private static let sizeFilter = FileFilter.fileSize(1024...)
    private static let combinedFilter = imageFilter.and(sizeFilter)
    
    init(url: URL) throws {
        var config = DirectoryWatcher.Configuration()
        config.filterChain.add(Self.combinedFilter)
        
        let watcher = try DirectoryWatcher(url: url, configuration: config)
    }
}
```

## Queue Configuration

Choose appropriate queues for your workload.

### Queue Selection Guidelines

```swift
var config = DirectoryWatcher.Configuration()

// CPU-intensive processing (image/video processing)
config.queue = .global(qos: .userInitiated)

// I/O intensive processing (file copying, network operations)  
config.queue = .global(qos: .utility)

// Background processing (logging, analytics)
config.queue = .global(qos: .background)

// UI updates (immediate user feedback required)
config.queue = .main

// Custom queue for fine-grained control
config.queue = DispatchQueue(label: "file-processing", qos: .userInitiated, attributes: .concurrent)
```

### Concurrent Processing

Handle multiple files concurrently:

```swift
watcher.onFilteredChange = { files in
    let processingQueue = DispatchQueue(label: "file-processing", attributes: .concurrent)
    let group = DispatchGroup()
    
    for file in files {
        group.enter()
        processingQueue.async {
            defer { group.leave() }
            processFile(file)
        }
    }
    
    group.notify(queue: .main) {
        print("All files processed")
    }
}
```

## Memory Management

Optimize memory usage for long-running applications.

### Ignore List Management

```swift
class MemoryEfficientWatcher {
    private let watcher: DirectoryWatcher
    private let cleanupTimer: Timer
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        
        // Periodic cleanup to prevent memory growth
        self.cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            self.watcher.configuration.ignoreList.cleanup()
        }
        
        // Limit ignore list size
        watcher.onDirectoryChange = { [weak self] url in
            guard let self = self else { return }
            
            if self.watcher.configuration.ignoreList.ignoredCount > 10000 {
                self.watcher.configuration.ignoreList.clearIgnored()
            }
            
            self.processChange(url)
        }
    }
    
    deinit {
        cleanupTimer.invalidate()
        watcher.stop()
    }
}
```

### Resource Pooling

Reuse expensive resources:

```swift
class PooledProcessor {
    private let imageProcessingQueue = OperationQueue()
    private let urlSession = URLSession.shared
    
    init() {
        imageProcessingQueue.maxConcurrentOperationCount = 4
        imageProcessingQueue.qualityOfService = .userInitiated
    }
    
    func processFiles(_ files: [URL]) {
        for file in files {
            let operation = BlockOperation {
                self.processFile(file)
            }
            imageProcessingQueue.addOperation(operation)
        }
    }
}
```

## Recursive Monitoring Optimization

Optimize recursive monitoring for large directory trees.

### Depth Limiting

```swift
var options = RecursiveWatchOptions()

// Limit depth for performance
options.maxDepth = 5  // Prevent excessive nesting

// Strategic exclusions
options.excludePatterns = [
    ".git",           // Version control
    "node_modules",   // Package dependencies
    "build",          // Build artifacts
    ".build",         // Swift build artifacts
    "DerivedData",    // Xcode artifacts
    "*.xcworkspace",  // Xcode workspace internals
    "Pods",           // CocoaPods
    ".tmp",           // Temporary directories
    "cache",          // Cache directories
    "log",            // Log directories
]
```

### Selective Monitoring

Monitor only what you need:

```swift
class SelectiveRecursiveWatcher {
    private var watchers: [DirectoryWatcher] = []
    
    func watchProject(at url: URL) throws {
        // Only watch specific subdirectories
        let importantPaths = [
            "Sources",
            "Tests", 
            "Resources"
        ]
        
        for path in importantPaths {
            let subdirectory = url.appendingPathComponent(path)
            if subdirectory.isDirectory {
                let watcher = try DirectoryWatcher(url: subdirectory)
                watcher.addFilter(.fileExtensions(["swift", "m", "h"]))
                watchers.append(watcher)
            }
        }
        
        watchers.forEach { $0.start() }
    }
}
```

## Benchmarking and Monitoring

Monitor performance to identify bottlenecks.

### Performance Monitoring

```swift
class MonitoredWatcher {
    private let watcher: DirectoryWatcher
    private var metrics = WatcherMetrics()
    
    struct WatcherMetrics {
        var eventCount = 0
        var totalProcessingTime: TimeInterval = 0
        var averageProcessingTime: TimeInterval { 
            totalProcessingTime / Double(max(eventCount, 1))
        }
        var eventsPerSecond: Double = 0
        var startTime = Date()
    }
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        
        watcher.onDirectoryChange = { [weak self] url in
            self?.recordEvent {
                self?.processChange(url)
            }
        }
        
        // Periodic reporting
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.reportMetrics()
        }
    }
    
    private func recordEvent(processing: () -> Void) {
        let startTime = Date()
        
        processing()
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        metrics.eventCount += 1
        metrics.totalProcessingTime += processingTime
        
        let elapsed = Date().timeIntervalSince(metrics.startTime)
        metrics.eventsPerSecond = Double(metrics.eventCount) / elapsed
    }
    
    private func reportMetrics() {
        print("""
        FSWatcher Metrics:
        - Events processed: \(metrics.eventCount)
        - Average processing time: \(String(format: "%.3f", metrics.averageProcessingTime * 1000))ms
        - Events per second: \(String(format: "%.1f", metrics.eventsPerSecond))
        """)
        
        // Alert if performance degrades
        if metrics.averageProcessingTime > 0.1 {
            print("⚠️ Processing time is high")
        }
        
        if metrics.eventsPerSecond > 1000 {
            print("⚠️ Very high event frequency")
        }
    }
}
```

### Profiling Tools

Use Xcode Instruments to profile:

```swift
// Enable detailed profiling in debug builds
#if DEBUG
class ProfilingWatcher {
    private let watcher: DirectoryWatcher
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        
        watcher.onDirectoryChange = { url in
            os_signpost(.event, log: .default, name: "DirectoryChanged", "URL: %@", url.path)
            // Your processing code here
        }
    }
}
#endif
```

## Performance Best Practices

### 1. Right-size Your Configuration

```swift
// ✅ Good: Tailored to use case
var config = DirectoryWatcher.Configuration()
config.debounceInterval = 0.5        // Appropriate for use case
config.filterChain.add(.imageFiles)  // Only watch what you need
config.queue = .global(qos: .utility) // Match processing requirements

// ❌ Bad: One-size-fits-all
var config = DirectoryWatcher.Configuration()
// Using all defaults without consideration
```

### 2. Efficient Event Handling

```swift
// ✅ Good: Efficient processing
watcher.onFilteredChange = { files in
    // Process in batches
    let batches = files.chunked(into: 10)
    for batch in batches {
        processBatch(batch)
    }
}

// ❌ Bad: Inefficient processing  
watcher.onDirectoryChange = { _ in
    // Scanning entire directory on every change
    let allFiles = try! FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    for file in allFiles {
        processFile(file) // Processing everything
    }
}
```

### 3. Resource Lifecycle Management

```swift
class WellManagedWatcher {
    private let watcher: DirectoryWatcher
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
    }
    
    func start() {
        watcher.start()
    }
    
    func pause() {
        watcher.stop() // Free resources when not needed
    }
    
    func resume() {
        watcher.start()
    }
    
    deinit {
        watcher.stop() // Ensure cleanup
    }
}
```

## Troubleshooting Performance Issues

### Common Performance Problems

1. **High CPU usage**: Check debounce interval and filter efficiency
2. **Memory growth**: Monitor ignore list size and cleanup frequency
3. **High latency**: Verify queue configuration and processing complexity
4. **Thread contention**: Ensure appropriate queue usage

### Diagnostic Commands

```swift
// Check current configuration
print("Debounce interval: \(watcher.configuration.debounceInterval)")
print("Filter count: \(watcher.configuration.filterChain.count)")
print("Ignored files: \(watcher.configuration.ignoreList.ignoredCount)")

// Monitor queue usage
print("Current queue: \(watcher.configuration.queue.label)")
```

## Platform-Specific Optimizations

### macOS Optimizations

```swift
#if os(macOS)
// Take advantage of macOS-specific features
var config = DirectoryWatcher.Configuration()
config.eventMask = [.write, .extend] // Reduce event types if possible
#endif
```

### iOS Optimizations

```swift
#if os(iOS)
// iOS-specific optimizations
var config = DirectoryWatcher.Configuration()
config.debounceInterval = 1.0 // Higher debouncing for mobile
config.queue = .global(qos: .background) // Be conservative with resources
#endif
```

Remember: Always measure performance before and after optimizations to ensure they're effective for your specific use case.
