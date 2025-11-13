Using my apps is also a way to [support me](https://5km.tech):

<p align="center">
  <a href="https://zipic.app"><img src="https://5km.tech/products/zipic/icon.png" width="60" height="60" alt="Zipic" style="border-radius: 12px; margin: 4px;"></a>
  <a href="https://orchard.5km.tech"><img src="https://5km.tech/products/orchard/icon.png" width="60" height="60" alt="Orchard" style="border-radius: 12px; margin: 4px;"></a>
  <a href="https://apps.apple.com/cn/app/timego-clock/id6448658165?l=en-GB&mt=12"><img src="https://5km.tech/products/timego/icon.png" width="60" height="60" alt="TimeGo Clock" style="border-radius: 12px; margin: 4px;"></a>
  <a href="https://keygengo.5km.tech"><img src="https://5km.tech/products/keygengo/icon.png" width="60" height="60" alt="KeygenGo" style="border-radius: 12px; margin: 4px;"></a>
  <a href="https://hipixel.5km.tech"><img src="https://5km.tech/products/hipixel/icon.png" width="60" height="60" alt="HiPixel" style="border-radius: 12px; margin: 4px;"></a>
</p>

---

# FSWatcher

![Swift](https://img.shields.io/badge/swift-5.9-orange.svg)
![Platform](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

A high-performance, Swift-native file system watcher for macOS and iOS that provides intelligent monitoring of directory changes with minimal system resource usage.

## Features

✨ **Event-Driven Architecture** - Uses `DispatchSource` for efficient file system monitoring  
🎯 **Smart Filtering** - Advanced filter chains with support for file types, sizes, and patterns  
🔍 **Predictive Ignoring** - Avoid monitoring self-generated files  
📁 **Recursive Monitoring** - Watch entire directory trees with configurable depth  
⚡ **Modern Swift** - Full support for Combine, Swift Concurrency, and structured concurrency  
🛡️ **Thread-Safe** - Designed for concurrent use across multiple threads  
📊 **Low Resource Usage** - Minimal CPU and memory footprint  

## Installation

### Swift Package Manager

Add FSWatcher to your project through Xcode or by adding it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/okooo5km/FSWatcher.git", from: "1.0.0")
]
```

## Quick Start

### Basic Usage

```swift
import FSWatcher

// Create a watcher for a directory
let watcher = try DirectoryWatcher(url: URL(fileURLWithPath: "/Users/user/Documents"))

// Set up event handler
watcher.onDirectoryChange = { url in
    print("Directory changed: \\(url.path)")
}

// Start watching
watcher.start()
```

### Filtered Watching

```swift
// Watch only image files larger than 1KB
var config = DirectoryWatcher.Configuration()
config.filterChain.add(.imageFiles)
config.filterChain.add(.fileSize(1024...))

let watcher = try DirectoryWatcher(url: watchURL, configuration: config)

watcher.onFilteredChange = { imageFiles in
    print("New images: \\(imageFiles.map { $0.lastPathComponent })")
}
```

### Multiple Directories

```swift
let multiWatcher = MultiDirectoryWatcher()
multiWatcher.onDirectoryChange = { url in
    print("Change in: \\(url.path)")
}

multiWatcher.startWatching(directories: [documentsURL, downloadsURL])
```

### Recursive Monitoring

```swift
var options = RecursiveWatchOptions()
options.maxDepth = 5
options.excludePatterns = ["node_modules", ".git", "*.tmp"]

let recursiveWatcher = try RecursiveDirectoryWatcher(
    url: projectURL, 
    options: options
)
```

### Multiple Recursive Directories

```swift
var options = RecursiveWatchOptions()
options.maxDepth = 3
options.excludePatterns = [".git", "node_modules", "*.tmp"]

let multiRecursiveWatcher = MultiRecursiveDirectoryWatcher(options: options)
multiRecursiveWatcher.onDirectoryChange = { url in
    print("Change detected: \\(url.path)")
}

multiRecursiveWatcher.startWatching(directories: [
    projectURL1,
    projectURL2,
    projectURL3
])
```

## Advanced Features

### Smart Filtering System

FSWatcher provides a powerful filtering system that can be chained together:

```swift
// Combine multiple filters
watcher.addFilter(
    .fileExtensions(["swift", "m"])
        .and(.fileSize(1000...))
        .and(.modifiedWithin(3600))
)

// Pre-built filter types
config.filterChain.add(.imageFiles)      // Images
config.filterChain.add(.videoFiles)      // Videos  
config.filterChain.add(.documentFiles)   // Documents
config.filterChain.add(.directoriesOnly) // Directories only
```

### Predictive Ignoring

Prevent monitoring your own output files:

```swift
// Set up a transform predictor
let predictor = FileTransformPredictor.imageCompression(suffix: "_compressed")
config.transformPredictor = predictor

// The watcher will automatically ignore predicted output files
watcher.onFilteredChange = { newImages in
    for image in newImages {
        compressImage(image) // Output will be automatically ignored
    }
}
```

### Combine Integration

```swift
import Combine

watcher.directoryChangePublisher
    .debounce(for: .seconds(1), scheduler: RunLoop.main)
    .sink { url in
        print("Debounced change: \\(url.path)")
    }
    .store(in: &cancellables)
```

### Swift Concurrency

```swift
watcher.start()

for await url in watcher.directoryChanges {
    await processChange(at: url)
}
```

## Configuration Options

### DirectoryWatcher.Configuration

```swift
var config = DirectoryWatcher.Configuration()

// Debounce interval (default: 0.5 seconds)
config.debounceInterval = 1.0

// File system events to monitor
config.eventMask = [.write, .extend, .delete, .rename]

// Processing queue
config.queue = .global(qos: .userInitiated)

// Filter chain
config.filterChain.add(.imageFiles)

// Ignore list management
config.ignoreList.addIgnorePattern("*.tmp")

// Transform prediction
config.transformPredictor = FileTransformPredictor.imageCompression()
```

## Error Handling

```swift
watcher.onError = { error in
    switch error {
    case .cannotOpenDirectory(let url):
        print("Cannot open: \\(url.path)")
    case .insufficientPermissions(let url):
        print("Permission denied: \\(url.path)")
    case .directoryNotFound(let url):
        print("Not found: \\(url.path)")
    default:
        print("Error: \\(error)")
    }
}
```

## Use Cases

### Image Processing Pipeline

Perfect for building image compression tools like [Zipic](https://zipic.app):

```swift
let pipeline = try ImageCompressionPipeline(
    watchDirectory: URL(fileURLWithPath: "/Users/user/ToCompress"),
    compressionQuality: 0.8
)

pipeline.start()
```

### Development Tool Hot Reload

Monitor source code changes:

```swift
let projectWatcher = try RecursiveDirectoryWatcher(url: projectURL)
projectWatcher.addFilter(.fileExtensions(["swift", "js", "css"]))

projectWatcher.onFilteredChange = { changedFiles in
    triggerHotReload(for: changedFiles)
}
```

### Automatic Backup System

```swift
let backupWatcher = try DirectoryWatcher(url: documentsURL)
backupWatcher.addFilter(.modifiedWithin(300)) // Last 5 minutes

backupWatcher.onFilteredChange = { recentFiles in
    performIncrementalBackup(files: recentFiles)
}
```

## Performance Considerations

- **Event-driven**: Only processes actual file system events, no polling
- **Debounced**: Prevents excessive event handling during rapid changes  
- **Filtered**: Process only relevant files using efficient filter chains
- **Resource management**: Automatic cleanup of file descriptors and resources

## Thread Safety

FSWatcher is designed to be thread-safe:

- All public APIs can be called from any thread
- Internal state is protected with appropriate synchronization
- Event handlers are called on the configured dispatch queue

## System Requirements

- **macOS**: 12.0+
- **iOS**: 15.0+
- **Swift**: 5.9+
- **Xcode**: 14.0+

## Documentation

- [API Documentation](docs/API.md)
- [Advanced Usage Guide](docs/Advanced.md)
- [Performance Tuning](docs/Performance.md)

## Examples

The `Examples/` directory contains complete, runnable examples:

- `BasicUsage.swift` - Fundamental usage patterns
- `ImageCompression.swift` - Complete image processing pipeline
- `HotReload.swift` - Development tool integration

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

## License

FSWatcher is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Acknowledgments

FSWatcher was inspired by the successful file monitoring implementation in [Zipic](https://zipic.app), a popular image compression tool for macOS. The design focuses on performance, reliability, and developer experience learned from real-world usage.

---

Made with ❤️ for the Swift community
