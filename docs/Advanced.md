# Advanced Usage Guide

## Advanced Filtering Techniques

### Complex Filter Combinations

You can combine multiple filters using boolean logic:

```swift
let complexFilter = FileFilter.imageFiles
    .and(.fileSize(1024...))
    .and(.modifiedWithin(3600))
    .or(.fileExtensions(["pdf"]))

watcher.addFilter(complexFilter)
```

### Custom Predicate Filters

Create sophisticated custom filters:

```swift
let advancedFilter = FileFilter.custom { url in
    // Only process files that are not currently being written to
    guard let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
        return false
    }
    
    // Allow files that haven't been modified in the last 2 seconds
    let timeSinceModification = Date().timeIntervalSince(resourceValues.contentModificationDate ?? Date.distantPast)
    return timeSinceModification > 2.0
}
```

### Filter Chain Strategies

Different filter chain approaches:

```swift
// AND strategy (all filters must match)
filterChain.add(.imageFiles)
filterChain.add(.fileSize(1024...))
let andResults = filterChain.filter(urls)

// OR strategy (any filter can match)
let orResults = filterChain.filterAny(urls)
```

## Predictive Ignoring Patterns

### Image Processing Pipeline

Prevent monitoring your own output files:

```swift
let imageProcessor = FileTransformPredictor.imageCompression(suffix: "_optimized")
config.transformPredictor = imageProcessor

watcher.onFilteredChange = { newImages in
    for image in newImages {
        // Predict and ignore output files before processing
        let predictedOutputs = imageProcessor.predictOutputFiles(for: image)
        watcher.addPredictiveIgnore(predictedOutputs)
        
        // Process image
        processImage(image) { outputURL in
            // Add actual output to ignore list
            watcher.addIgnoredFiles([outputURL])
        }
    }
}
```

### Build System Integration

Ignore generated build artifacts:

```swift
let buildPredictor = FileTransformPredictor(rules: [
    .init(inputPattern: ".*\\.swift$", outputTemplate: "build/{name}.o"),
    .init(inputPattern: ".*\\.m$", outputTemplate: "build/{name}.o"),
    .init(inputPattern: ".*\\.c$", outputTemplate: "build/{name}.o")
])

config.transformPredictor = buildPredictor
```

## Recursive Monitoring Strategies

### Project Structure Monitoring

Monitor a development project with intelligent exclusions:

```swift
var options = RecursiveWatchOptions()
options.maxDepth = 10
options.followSymlinks = false
options.excludePatterns = [
    ".git",
    "node_modules", 
    "build",
    "*.xcworkspace",
    "DerivedData",
    ".build",
    "Pods"
]

let projectWatcher = try RecursiveDirectoryWatcher(
    url: projectURL,
    options: options
)

// Only watch source files
projectWatcher.addFilter(
    .fileExtensions(["swift", "m", "h", "cpp", "c"])
        .and(.fileSize(1...))  // Ignore empty files
)
```

### Content Management System

Monitor content directories with smart categorization:

```swift
let contentWatcher = try RecursiveDirectoryWatcher(url: contentRoot)

// Different handlers for different content types
contentWatcher.onFilteredChange = { changedFiles in
    let images = changedFiles.filter { FileFilter.imageFiles.matches($0) }
    let documents = changedFiles.filter { FileFilter.documentFiles.matches($0) }
    let videos = changedFiles.filter { FileFilter.videoFiles.matches($0) }
    
    if !images.isEmpty {
        processImages(images)
    }
    
    if !documents.isEmpty {
        processDocuments(documents)
    }
    
    if !videos.isEmpty {
        processVideos(videos)
    }
}
```

## Performance Optimization

### Debouncing Strategies

Adjust debouncing for different scenarios:

```swift
// High-frequency scenarios (log processing)
var highFreqConfig = DirectoryWatcher.Configuration()
highFreqConfig.debounceInterval = 0.1

// Batch processing scenarios
var batchConfig = DirectoryWatcher.Configuration()
batchConfig.debounceInterval = 2.0

// Real-time scenarios
var realtimeConfig = DirectoryWatcher.Configuration()
realtimeConfig.debounceInterval = 0.01
```

### Queue Management

Use appropriate queues for different workloads:

```swift
// CPU-intensive processing
config.queue = .global(qos: .userInitiated)

// Background processing
config.queue = .global(qos: .background)

// UI-related updates
config.queue = .main
```

### Memory Management

Implement cleanup strategies for long-running watchers:

```swift
class LongRunningWatcher {
    private let watcher: DirectoryWatcher
    private var cleanupTimer: Timer?
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        
        // Cleanup ignore list every hour
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            self.watcher.configuration.ignoreList.cleanup()
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        watcher.stop()
    }
}
```

## Error Handling and Recovery

### Robust Error Handling

Implement comprehensive error handling:

```swift
class RobustFileWatcher {
    private var watcher: DirectoryWatcher?
    private let watchURL: URL
    private let maxRetries = 3
    private var retryCount = 0
    
    init(url: URL) {
        self.watchURL = url
        startWatching()
    }
    
    private func startWatching() {
        do {
            watcher = try DirectoryWatcher(url: watchURL)
            
            watcher?.onError = { [weak self] error in
                self?.handleError(error)
            }
            
            watcher?.onDirectoryChange = { [weak self] url in
                self?.resetRetryCount()
                self?.processChange(at: url)
            }
            
            watcher?.start()
            
        } catch {
            handleError(error)
        }
    }
    
    private func handleError(_ error: Error) {
        print("Watcher error: \(error)")
        
        guard retryCount < maxRetries else {
            print("Max retries exceeded, giving up")
            return
        }
        
        retryCount += 1
        
        // Exponential backoff
        let delay = pow(2.0, Double(retryCount))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.startWatching()
        }
    }
    
    private func resetRetryCount() {
        retryCount = 0
    }
}
```

### Permission Handling

Handle permission-related errors gracefully:

```swift
watcher.onError = { error in
    switch error {
    case .insufficientPermissions(let url):
        // Request permission or show user guidance
        requestFileSystemPermission(for: url)
        
    case .directoryNotFound(let url):
        // Wait for directory to be created
        waitForDirectory(url)
        
    case .cannotOpenDirectory(let url):
        // Check if directory is accessible
        verifyDirectoryAccess(url)
        
    default:
        // Handle other errors
        print("Unhandled error: \(error)")
    }
}
```

## Integration with Other Systems

### Combine Integration Patterns

Advanced Combine usage:

```swift
import Combine

class CombineWatcherService {
    private let watcher: DirectoryWatcher
    private var cancellables = Set<AnyCancellable>()
    
    // Processed file publisher
    lazy var processedFiles = watcher.filteredChangePublisher
        .flatMap { files in
            Publishers.Sequence(sequence: files)
        }
        .filter { file in
            // Additional filtering
            file.pathExtension == "jpg"
        }
        .map { file in
            // Transform to processed format
            ProcessedFile(url: file)
        }
        .eraseToAnyPublisher()
    
    // Batch processing
    lazy var batchedChanges = watcher.directoryChangePublisher
        .collect(.byTime(DispatchQueue.main, .seconds(5)))
        .filter { !$0.isEmpty }
        .eraseToAnyPublisher()
        
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        processedFiles
            .sink { processedFile in
                self.handleProcessedFile(processedFile)
            }
            .store(in: &cancellables)
            
        batchedChanges
            .sink { batch in
                self.processBatch(batch)
            }
            .store(in: &cancellables)
    }
}
```

### Swift Concurrency Patterns

Modern async/await integration:

```swift
actor FileProcessor {
    private let watcher: DirectoryWatcher
    private var isProcessing = false
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        startProcessing()
    }
    
    private func startProcessing() {
        Task {
            for await url in watcher.directoryChanges {
                await processDirectory(url)
            }
        }
        
        Task {
            for await files in watcher.filteredChanges {
                await processFiles(files)
            }
        }
    }
    
    private func processDirectory(_ url: URL) async {
        // Process directory change
        print("Processing directory: \(url)")
    }
    
    private func processFiles(_ files: [URL]) async {
        guard !isProcessing else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Process files concurrently
        await withTaskGroup(of: Void.self) { group in
            for file in files {
                group.addTask {
                    await self.processFile(file)
                }
            }
        }
    }
    
    private func processFile(_ file: URL) async {
        // Async file processing
        print("Processing file: \(file)")
    }
}
```

## Testing and Debugging

### Unit Testing Watchers

Create testable watcher components:

```swift
class TestableWatcher {
    let watcher: DirectoryWatcher
    var events: [FileSystemEvent] = []
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        
        watcher.delegate = self
    }
}

extension TestableWatcher: DirectoryWatcherDelegate {
    func directoryDidChange(with event: FileSystemEvent) {
        events.append(event)
    }
    
    func directoryDidChange(at url: URL) {
        events.append(FileSystemEvent(url: url, eventType: .modified))
    }
}

// Usage in tests
func testWatcherDetectsChanges() {
    let tempDir = createTempDirectory()
    let testWatcher = try! TestableWatcher(url: tempDir)
    
    testWatcher.watcher.start()
    
    // Create test file
    let testFile = tempDir.appendingPathComponent("test.txt")
    try! "content".write(to: testFile, atomically: true, encoding: .utf8)
    
    // Wait for event
    wait(timeout: 2.0) {
        testWatcher.events.count > 0
    }
    
    XCTAssertEqual(testWatcher.events.count, 1)
    XCTAssertEqual(testWatcher.events.first?.url, tempDir)
}
```

### Performance Monitoring

Monitor watcher performance:

```swift
class MonitoredWatcher {
    private let watcher: DirectoryWatcher
    private var eventCount = 0
    private var startTime = Date()
    
    init(url: URL) throws {
        self.watcher = try DirectoryWatcher(url: url)
        
        watcher.onDirectoryChange = { [weak self] url in
            self?.recordEvent()
            self?.processChange(url)
        }
    }
    
    private func recordEvent() {
        eventCount += 1
        
        let elapsed = Date().timeIntervalSince(startTime)
        let eventsPerSecond = Double(eventCount) / elapsed
        
        print("Events/sec: \(eventsPerSecond)")
        
        // Log if performance degrades
        if eventsPerSecond > 100 {
            print("⚠️ High event frequency detected")
        }
    }
}
```
