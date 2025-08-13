# FSWatcher Swift Package 实现方案

## 概述

基于 Zipic 项目中成功实现的文件系统监控功能，我们计划将其抽离成一个独立、高效、可复用的 Swift Package。该包使用原生的 `DispatchSource` API 实现了低 CPU 占用的文件系统事件监控，相比传统的轮询方式，性能提升显著。

## 当前实现分析

### 技术特点

1. **事件驱动架构**：使用 `DispatchSource.makeFileSystemObjectSource` 监听文件系统事件
2. **低资源占用**：避免定时轮询，仅在文件系统事件发生时触发
3. **防抖机制**：使用 0.5 秒防抖间隔避免频繁触发
4. **多目录支持**：可同时监控多个目录
5. **代理模式**：使用 delegate 模式传递事件

### 核心组件

- `DirectoryWatcher`：单目录监控器
- `MultiDirectoryWatcher`：多目录监控管理器
- `DirectoryWatcherDelegate`：事件通知协议

## Swift Package 设计方案

### 1. 包基本信息

```plaintext
Package Name: FSWatcher
Swift Tools Version: 5.9
Platforms: macOS 12.0+, iOS 15.0+
```

### 2. 目录结构

```bash
FSWatcher/
├── Package.swift
├── README.md
├── Sources/
│   └── FSWatcher/
│       ├── Core/
│       │   ├── DirectoryWatcher.swift
│       │   ├── MultiDirectoryWatcher.swift
│       │   └── FileSystemEvent.swift
│       ├── Extensions/
│       │   └── URL+Extensions.swift
│       ├── Protocols/
│       │   └── DirectoryWatcherDelegate.swift
│       └── Utils/
│           └── DebounceTimer.swift
├── Tests/
│   └── FSWatcherTests/
│       ├── DirectoryWatcherTests.swift
│       └── MultiDirectoryWatcherTests.swift
└── Examples/
    └── FSWatcherExample/
        └── main.swift
```

### 3. 核心 API 设计

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
    
    private let configuration: Configuration
    
    public init(url: URL, configuration: Configuration = Configuration()) throws
    
    // Delegate 模式
    public weak var delegate: DirectoryWatcherDelegate?
    
    // 闭包模式
    public var onDirectoryChange: ((URL) -> Void)?
    public var onFilteredChange: (([URL]) -> Void)?  // 只返回通过过滤器的文件
    
    // Combine 支持
    public var directoryChangePublisher: AnyPublisher<URL, Never> { get }
    public var filteredChangePublisher: AnyPublisher<[URL], Never> { get }
    
    // Swift Concurrency 支持
    public var directoryChanges: AsyncStream<URL> { get }
    public var filteredChanges: AsyncStream<[URL]> { get }
    
    // 过滤器管理
    public func addFilter(_ filter: FileFilter)
    public func clearFilters()
    
    // 忽略列表管理
    public func addIgnoredFiles(_ urls: [URL])
    public func addPredictiveIgnore(_ urls: [URL])
    
    public func start()
    public func stop()
    public var isWatching: Bool { get }
}
```

#### 3.3 MultiDirectoryWatcher

```swift
public class MultiDirectoryWatcher {
    public init(configuration: DirectoryWatcher.Configuration = DirectoryWatcher.Configuration())
    
    // 多种事件处理模式
    public weak var delegate: DirectoryWatcherDelegate?
    public var onDirectoryChange: ((URL) -> Void)?
    public var directoryChangePublisher: AnyPublisher<URL, Never> { get }
    public var directoryChanges: AsyncStream<URL> { get }
    
    public func startWatching(directories: [URL])
    public func stopWatching(directory: URL)
    public func stopAllWatching()
    public var watchedDirectories: [URL] { get }
    public var isWatching: Bool { get }
}
```

#### 3.4 DirectoryWatcherDelegate

```swift
public protocol DirectoryWatcherDelegate: AnyObject {
    func directoryDidChange(at url: URL)
    
    // 可选的详细事件处理
    func directoryDidChange(with event: FileSystemEvent)
}

// 提供默认实现
extension DirectoryWatcherDelegate {
    func directoryDidChange(with event: FileSystemEvent) {
        directoryDidChange(at: event.url)
    }
}
```

### 4. 核心增强功能设计

#### 4.1 递归监控支持

```swift
public struct RecursiveWatchOptions {
    public var maxDepth: Int? = nil  // nil 表示无限深度
    public var followSymlinks: Bool = false
    public var excludePatterns: [String] = [] // glob 模式，如 "*.tmp", "node_modules"
}

public class RecursiveDirectoryWatcher: DirectoryWatcher {
    private var childWatchers: [URL: DirectoryWatcher] = [:]
    private let options: RecursiveWatchOptions
    
    public init(url: URL, options: RecursiveWatchOptions = RecursiveWatchOptions()) throws {
        self.options = options
        super.init(url: url)
    }
    
    private func scanAndWatchSubdirectories(at url: URL, currentDepth: Int = 0) {
        // 实现递归扫描和监控逻辑
    }
}
```

#### 4.2 智能过滤器链（基于 Zipic 的文件类型过滤）

```swift
import UniformTypeIdentifiers

public struct FileFilter {
    private let predicate: (URL) -> Bool
    
    // 文件扩展名过滤器
    public static func fileExtensions(_ extensions: [String]) -> FileFilter {
        FileFilter { url in
            extensions.contains(url.pathExtension.lowercased())
        }
    }
    
    // UTType 过滤器（借鉴 Zipic 的 isImageFile 实现）
    public static func utTypes(_ types: [UTType]) -> FileFilter {
        FileFilter { url in
            guard let fileUTI = UTType(filenameExtension: url.pathExtension) else { return false }
            return types.contains { $0.conforms(to: fileUTI) || fileUTI.conforms(to: $0) }
        }
    }
    
    // 便捷的图像文件过滤器
    public static var imageFiles: FileFilter {
        utTypes([.png, .jpeg, .webP, .heic, .avif, .tiff, .icns, .gif])
    }
    
    // 文件名模式过滤器
    public static func fileName(matching pattern: String) -> FileFilter {
        FileFilter { url in
            url.lastPathComponent.range(of: pattern, options: .regularExpression) != nil
        }
    }
    
    // 文件大小过滤器
    public static func fileSize(range: ClosedRange<Int>) -> FileFilter {
        FileFilter { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
            return range.contains(size)
        }
    }
    
    // 修改时间过滤器
    public static func modifiedWithin(_ interval: TimeInterval) -> FileFilter {
        FileFilter { url in
            guard let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { return false }
            return Date().timeIntervalSince(modDate) <= interval
        }
    }
    
    // 自定义过滤器
    public static func custom(_ predicate: @escaping (URL) -> Bool) -> FileFilter {
        FileFilter(predicate: predicate)
    }
    
    // 过滤器组合
    public func and(_ other: FileFilter) -> FileFilter {
        FileFilter { url in
            self.predicate(url) && other.predicate(url)
        }
    }
    
    public func or(_ other: FileFilter) -> FileFilter {
        FileFilter { url in
            self.predicate(url) || other.predicate(url)
        }
    }
    
    public func not() -> FileFilter {
        FileFilter { url in
            !self.predicate(url)
        }
    }
    
    internal func matches(_ url: URL) -> Bool {
        predicate(url)
    }
}

// 过滤器链支持
public struct FilterChain {
    private var filters: [FileFilter] = []
    
    public init() {}
    
    public mutating func add(_ filter: FileFilter) {
        filters.append(filter)
    }
    
    public func matches(_ url: URL) -> Bool {
        // 所有过滤器都必须匹配（AND 逻辑）
        return filters.allSatisfy { $0.matches(url) }
    }
}
```

#### 4.3 忽略列表机制（基于 Zipic 的白名单逻辑）

```swift
public class IgnoreList {
    private var ignoredFiles: Set<URL> = []
    private var predictiveIgnores: Set<URL> = []
    private let queue = DispatchQueue(label: "ignore-list", attributes: .concurrent)
    
    // 添加已处理的文件到忽略列表
    public func addIgnored(_ urls: [URL]) {
        queue.async(flags: .barrier) {
            self.ignoredFiles.formUnion(urls)
        }
    }
    
    // 预测性添加：在处理前就添加将要生成的文件
    // 类似 Zipic 在压缩前就将输出文件名加入白名单
    public func addPredictiveIgnore(_ urls: [URL]) {
        queue.async(flags: .barrier) {
            self.predictiveIgnores.formUnion(urls)
        }
    }
    
    // 检查文件是否应该被忽略
    public func shouldIgnore(_ url: URL) -> Bool {
        queue.sync {
            ignoredFiles.contains(url) || predictiveIgnores.contains(url)
        }
    }
    
    // 清理过期的忽略项
    public func cleanup() {
        queue.async(flags: .barrier) {
            // 移除不存在的文件
            self.ignoredFiles = self.ignoredFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
            self.predictiveIgnores = self.predictiveIgnores.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
    
    public func clear() {
        queue.async(flags: .barrier) {
            self.ignoredFiles.removeAll()
            self.predictiveIgnores.removeAll()
        }
    }
}

// 文件转换预测器（类似 Zipic 的格式转换逻辑）
public struct FileTransformPredictor {
    public struct TransformRule {
        public let inputPattern: String  // 输入文件模式
        public let outputTemplate: String  // 输出文件名模板
        public let formatChange: Bool  // 是否改变格式
        
        public init(inputPattern: String, outputTemplate: String, formatChange: Bool = false) {
            self.inputPattern = inputPattern
            self.outputTemplate = outputTemplate
            self.formatChange = formatChange
        }
    }
    
    private let rules: [TransformRule]
    
    public init(rules: [TransformRule]) {
        self.rules = rules
    }
    
    // 预测给定文件的输出文件名
    public func predictOutputFiles(for inputURL: URL) -> [URL] {
        var outputs: [URL] = []
        let fileName = inputURL.deletingPathExtension().lastPathComponent
        let directory = inputURL.deletingLastPathComponent()
        
        for rule in rules {
            if inputURL.lastPathComponent.range(of: rule.inputPattern, options: .regularExpression) != nil {
                // 应用模板生成输出文件名
                let outputName = rule.outputTemplate.replacingOccurrences(of: "{name}", with: fileName)
                let outputURL = directory.appendingPathComponent(outputName)
                outputs.append(outputURL)
            }
        }
        
        return outputs
    }
}
```

#### 4.4 批处理支持

```swift
public struct BatchConfiguration {
    public var maxBatchSize: Int = 10
    public var maxBatchInterval: TimeInterval = 1.0
}

// 批量事件处理
public var onBatchDirectoryChanges: (([URL]) -> Void)?
```

#### 4.5 错误处理

```swift
public enum FSWatcherError: Error, LocalizedError {
    case cannotOpenDirectory(URL)
    case insufficientPermissions(URL)
    case directoryNotFound(URL)
    case systemResourcesUnavailable
    
    public var errorDescription: String? { /* 实现 */ }
}

// 错误回调
public var onError: ((FSWatcherError) -> Void)?
```

### 5. 实现细节

#### 5.1 防抖机制优化

```swift
internal class DebounceTimer {
    private var timer: Timer?
    private let interval: TimeInterval
    private let queue: DispatchQueue
    
    init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }
    
    func debounce(_ action: @escaping () -> Void) {
        timer?.invalidate()
        queue.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: false) { _ in
                action()
            }
        }
    }
}
```

#### 5.2 Combine 集成

```swift
import Combine

private let _directoryChangeSubject = PassthroughSubject<URL, Never>()

public var directoryChangePublisher: AnyPublisher<URL, Never> {
    _directoryChangeSubject.eraseToAnyPublisher()
}
```

#### 5.3 Swift Concurrency 支持

```swift
public var directoryChanges: AsyncStream<URL> {
    AsyncStream { continuation in
        let id = UUID()
        
        // 存储 continuation 用于后续发送事件
        continuations[id] = continuation
        
        continuation.onTermination = { _ in
            continuations.removeValue(forKey: id)
        }
    }
}
```

### 6. 性能优化

#### 6.1 资源管理

- 使用 `deinit` 确保文件描述符正确关闭
- 实现引用计数避免重复监控同一目录
- 支持暂停/恢复功能减少资源占用

#### 6.2 内存优化

- 使用 `weak` 引用避免循环引用
- 及时清理不再需要的监控器
- 合理使用队列避免主线程阻塞

### 7. 使用示例与应用场景

#### 7.1 基础用法

```swift
import FSWatcher

// 监控单个目录
let watcher = try DirectoryWatcher(url: URL(fileURLWithPath: "/Users/user/Documents"))

// 使用闭包
watcher.onDirectoryChange = { url in
    print("Directory changed: \(url)")
}

watcher.start()
```

#### 7.2 智能过滤器链使用

```swift
// 配置过滤器：只监控图像文件
var config = DirectoryWatcher.Configuration()
config.filterChain.add(.imageFiles)
config.filterChain.add(.fileSize(1024...))

let watcher = try DirectoryWatcher(
    url: URL(fileURLWithPath: "/Users/user/Pictures"),
    configuration: config
)

// 只处理过滤后的文件
watcher.onFilteredChange = { imageFiles in
    print("New image files detected: \(imageFiles.map { $0.lastPathComponent })")
    // 触发图像处理流程
}
```

#### 7.3 类似 Zipic 的图像压缩场景

```swift
// 设置转换预测器（类似 Zipic 的格式转换逻辑）
let predictor = FileTransformPredictor(rules: [
    // 原始 JPEG 转换为压缩版本
    .init(inputPattern: ".*\\.jpe?g$", outputTemplate: "{name}_compressed.jpg"),
    // PNG 转换为 WebP
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
        // 预测输出文件并添加到忽略列表
        let predictedOutputs = predictor.predictOutputFiles(for: imageURL)
        imageWatcher.addPredictiveIgnore(predictedOutputs)
        
        // 开始压缩处理
        compressImage(imageURL) { compressedURL in
            // 压缩完成后，将实际生成的文件添加到忽略列表
            imageWatcher.addIgnoredFiles([compressedURL])
        }
    }
}
```

#### 7.4 递归监控使用

```swift
// 递归监控项目目录，排除常见的临时文件
var recursiveOptions = RecursiveWatchOptions()
recursiveOptions.maxDepth = 5
recursiveOptions.excludePatterns = ["node_modules", ".git", "*.tmp", ".DS_Store"]

let projectWatcher = try RecursiveDirectoryWatcher(
    url: URL(fileURLWithPath: "/Users/user/MyProject"),
    options: recursiveOptions
)

// 只监控源代码文件
projectWatcher.addFilter(.fileExtensions(["swift", "js", "ts", "py"]))

projectWatcher.onFilteredChange = { changedFiles in
    print("Source files changed, triggering build...")
    triggerBuild()
}
```

#### 7.5 多目录监控

```swift
let multiWatcher = MultiDirectoryWatcher()
multiWatcher.onDirectoryChange = { url in
    print("Directory changed: \(url)")
}

let directories = [
    URL(fileURLWithPath: "/Users/user/Documents"),
    URL(fileURLWithPath: "/Users/user/Downloads")
]
multiWatcher.startWatching(directories: directories)
```

#### 7.6 Combine 使用

```swift
import Combine

let cancellable = watcher.filteredChangePublisher
    .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
    .sink { newFiles in
        print("Filtered files changed: \(newFiles)")
    }
```

#### 7.7 Swift Concurrency 使用

```swift
Task {
    for await newFiles in watcher.filteredChanges {
        print("Processing \(newFiles.count) new files")
        await processFiles(newFiles)
    }
}
```

### 8. 典型应用场景详解

#### 8.1 图像处理管道（如 Zipic）

```swift
class ImageCompressionPipeline {
    private let watcher: DirectoryWatcher
    private let compressionQueue = OperationQueue()
    
    init(watchDirectory: URL) throws {
        var config = DirectoryWatcher.Configuration()
        config.filterChain.add(.imageFiles)
        config.filterChain.add(.fileSize(1024...))  // 至少 1KB
        
        // 预测压缩后的文件名
        let predictor = FileTransformPredictor(rules: [
            .init(inputPattern: ".*", outputTemplate: "{name}_compressed")
        ])
        config.transformPredictor = predictor
        
        self.watcher = try DirectoryWatcher(url: watchDirectory, configuration: config)
        
        watcher.onFilteredChange = { [weak self] newImages in
            self?.processNewImages(newImages)
        }
    }
    
    private func processNewImages(_ images: [URL]) {
        for imageURL in images {
            let operation = ImageCompressionOperation(inputURL: imageURL)
            operation.completionBlock = { [weak self] in
                // 压缩完成后更新忽略列表
                if let outputURL = operation.outputURL {
                    self?.watcher.addIgnoredFiles([outputURL])
                }
            }
            compressionQueue.addOperation(operation)
        }
    }
    
    func start() {
        watcher.start()
    }
}
```

#### 8.2 开发工具热重载

```swift
class HotReloadWatcher {
    private let projectWatcher: RecursiveDirectoryWatcher
    
    init(projectRoot: URL) throws {
        var options = RecursiveWatchOptions()
        options.excludePatterns = [".git", "node_modules", "*.log", "build"]
        
        self.projectWatcher = try RecursiveDirectoryWatcher(url: projectRoot, options: options)
        
        // 只监控源代码文件
        projectWatcher.addFilter(.fileExtensions(["swift", "js", "css", "html"]))
        
        projectWatcher.onFilteredChange = { changedFiles in
            NotificationCenter.default.post(
                name: .sourceCodeChanged,
                object: changedFiles
            )
        }
    }
}
```

#### 8.3 自动备份系统

```swift
class IncrementalBackupWatcher {
    private let watcher: DirectoryWatcher
    private var lastBackupTime = Date()
    
    init(sourceDirectory: URL) throws {
        self.watcher = try DirectoryWatcher(url: sourceDirectory)
        
        // 过滤掉临时文件和系统文件
        watcher.addFilter(.fileName(matching: "^(?!\\.DS_Store|.*\\.tmp$).*"))
        watcher.addFilter(.modifiedWithin(3600)) // 只备份最近1小时修改的
        
        watcher.onFilteredChange = { [weak self] changedFiles in
            self?.performIncrementalBackup(changedFiles)
        }
    }
    
    private func performIncrementalBackup(_ files: [URL]) {
        // 执行增量备份逻辑
        for file in files {
            backupFile(file)
        }
        lastBackupTime = Date()
    }
}
```

#### 8.4 内容管理系统

```swift
class StaticSiteGenerator {
    private let contentWatcher: DirectoryWatcher
    
    init(contentDirectory: URL) throws {
        var config = DirectoryWatcher.Configuration()
        config.filterChain.add(.fileExtensions(["md", "html", "css", "js"]))
        
        self.contentWatcher = try DirectoryWatcher(url: contentDirectory, configuration: config)
        
        contentWatcher.onFilteredChange = { changedFiles in
            print("Content changed, regenerating site...")
            self.regenerateSite(affectedFiles: changedFiles)
        }
    }
    
    private func regenerateSite(affectedFiles: [URL]) {
        // 重新生成静态站点
        for file in affectedFiles {
            if file.pathExtension == "md" {
                generateHTMLFromMarkdown(file)
            }
        }
        deployToServer()
    }
}
```

### 8. Package.swift 配置

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FSWatcher",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "FSWatcher",
            targets: ["FSWatcher"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FSWatcher",
            dependencies: []
        ),
        .testTarget(
            name: "FSWatcherTests",
            dependencies: ["FSWatcher"]
        ),
    ]
)
```

### 9. 测试策略

#### 9.1 单元测试

- 测试基本的监控功能
- 测试防抖机制
- 测试错误处理
- 测试资源清理

#### 9.2 集成测试

- 测试多目录监控
- 测试并发场景
- 测试长时间运行稳定性

### 10. 最佳实践

#### 10.1 使用建议

1. 合理设置防抖间隔，避免过于频繁的事件处理
2. 使用适当的 DispatchQueue 避免阻塞主线程
3. 及时停止不需要的监控以释放系统资源
4. 处理权限问题和错误情况

#### 10.2 性能考虑

1. 避免监控过深的目录结构
2. 使用文件过滤器减少不必要的事件处理
3. 考虑使用批处理模式处理大量文件变化

### 11. 迁移指南

从现有 Zipic 实现迁移到 FSWatcher Package：

```swift
// 原有代码
let directoryWatcher = MultiDirectoryWatcher()
directoryWatcher.delegate = self

// 迁移后
import FSWatcher

let watcher = MultiDirectoryWatcher()
watcher.delegate = self
```

### 12. 版本规划

- **v1.0.0**：基础功能，支持单/多目录监控，简单过滤器
- **v1.1.0**：添加 Combine 和 Swift Concurrency 支持
- **v1.2.0**：添加智能过滤器链和忽略列表机制
- **v1.3.0**：添加递归监控和文件转换预测器
- **v1.4.0**：添加批处理和性能监控功能
- **v2.0.0**：添加网络文件系统支持、事件录制回放等高级功能

### 13. 从 Zipic 学到的关键设计理念

#### 13.1 预防性设计

**Zipic 的白名单机制给我们的启发**：

- 在处理前就预测并忽略输出文件，避免无限循环
- 这种预防性思维可以推广到其他场景，如编译器监控源代码时忽略生成的目标文件

#### 13.2 智能过滤的重要性

**从 `isImageFile` 的实现学习**：

- 使用 UTType 进行精确的文件类型判断
- 支持多种格式的统一处理
- 可扩展的类型系统设计

#### 13.3 性能优先的架构选择

**DispatchSource vs 轮询的优势**：

- 事件驱动比定时检查更高效
- 系统级集成比应用层轮询更可靠
- 资源占用更少，响应更及时

### 14. 竞品对比与定位

| 特性 | FSWatcher | fswatch | Watchman | chokidar |
|------|-----------|---------|----------|----------|
| 语言 | Pure Swift | C++ | C/Python | JavaScript |
| 平台 | Apple 生态 | 跨平台 | 跨平台 | Node.js |
| 性能 | 原生优化 | 高性能 | Facebook 级 | 中等 |
| 易用性 | Swift 友好 | 命令行 | 复杂配置 | JS 生态 |
| 现代特性 | Combine/Async | 无 | 部分支持 | Promise |
| 过滤能力 | 智能链式 | 基础 | 强大 | 中等 |
| 忽略机制 | 预测性 | 静态 | 静态 | 静态 |

**FSWatcher 的独特优势**：

1. **原生 Swift 性能**：无桥接损耗
2. **现代 API 设计**：支持最新 Swift 特性
3. **预测性忽略**：从 Zipic 学来的独特机制
4. **Apple 生态优化**：深度集成 macOS/iOS 特性

## 结论

基于 Zipic 项目的成功实现和深度分析，FSWatcher Swift Package 将提供一个高性能、低资源占用、智能化的文件系统监控解决方案。

**核心价值**：

1. **事件驱动架构**：使用 DispatchSource 实现高效监控
2. **智能过滤系统**：基于 UTType 的精确文件类型识别
3. **预测性忽略**：避免监控自己生成的文件，防止无限循环
4. **现代 Swift 支持**：Combine、Swift Concurrency 等
5. **递归监控**：可配置深度的子目录监控
6. **丰富的应用场景**：从图像处理到开发工具，从备份系统到内容管理

这个实现方案不仅解决了文件系统监控的技术问题，更重要的是提供了一套完整的、可扩展的、符合现代开发实践的解决方案。通过从 Zipic 的成功经验中学习，我们能够为 Swift 开发者提供一个真正实用、高效的文件监控工具。
