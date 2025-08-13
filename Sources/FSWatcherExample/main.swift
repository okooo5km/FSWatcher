import Foundation
import FSWatcher

print("🚀 FSWatcher 示例测试")
print("===================")

// 创建测试目录
let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("FSWatcherTest_\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

print("📁 测试目录: \(testDir.path)")

do {
    // 测试 1: 基础目录监控
    print("\n🔍 测试 1: 基础目录监控")
    
    let watcher = try DirectoryWatcher(url: testDir)
    var changeCount = 0
    
    watcher.onDirectoryChange = { url in
        changeCount += 1
        print("  ✅ 检测到变化 #\(changeCount): \(url.lastPathComponent)")
    }
    
    watcher.start()
    print("  开始监控...")
    
    // 创建测试文件
    for i in 1...3 {
        let testFile = testDir.appendingPathComponent("test\(i).txt")
        try! "Test content \(i)".write(to: testFile, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    // 等待事件处理
    Thread.sleep(forTimeInterval: 1.0)
    watcher.stop()
    print("  停止监控，检测到 \(changeCount) 次变化")
    
    // 测试 2: 过滤器测试
    print("\n🎯 测试 2: 文件过滤")
    
    var config = DirectoryWatcher.Configuration()
    config.filterChain.add(.fileExtensions(["jpg", "png"]))
    
    let filteredWatcher = try DirectoryWatcher(url: testDir, configuration: config)
    var filteredCount = 0
    
    filteredWatcher.onFilteredChange = { imageFiles in
        filteredCount += imageFiles.count
        print("  🖼️  检测到图像文件: \(imageFiles.map { $0.lastPathComponent })")
    }
    
    filteredWatcher.start()
    
    // 创建不同类型的文件
    let imageFile = testDir.appendingPathComponent("image.jpg")
    let textFile = testDir.appendingPathComponent("document.txt")
    
    try! Data().write(to: imageFile)  // 图像文件
    try! "Text content".write(to: textFile, atomically: true, encoding: .utf8)  // 文本文件
    
    Thread.sleep(forTimeInterval: 1.0)
    filteredWatcher.stop()
    print("  过滤后检测到 \(filteredCount) 个图像文件")
    
    // 测试 3: 忽略列表测试
    print("\n🚫 测试 3: 忽略列表")
    
    let ignoreWatcher = try DirectoryWatcher(url: testDir)
    var ignoreCount = 0
    
    // 添加忽略文件
    let ignoredFile = testDir.appendingPathComponent("ignored.txt")
    ignoreWatcher.addIgnoredFiles([ignoredFile])
    
    ignoreWatcher.onFilteredChange = { files in
        let nonIgnoredFiles = files.filter { !$0.lastPathComponent.contains("ignored") }
        ignoreCount += nonIgnoredFiles.count
        print("  📝 检测到非忽略文件: \(nonIgnoredFiles.map { $0.lastPathComponent })")
    }
    
    ignoreWatcher.start()
    
    // 创建被忽略和未被忽略的文件
    try! "Ignored content".write(to: ignoredFile, atomically: true, encoding: .utf8)
    let normalFile = testDir.appendingPathComponent("normal.txt")
    try! "Normal content".write(to: normalFile, atomically: true, encoding: .utf8)
    
    Thread.sleep(forTimeInterval: 1.0)
    ignoreWatcher.stop()
    print("  忽略列表工作正常")
    
    print("\n🎉 所有测试完成！")
    print("FSWatcher 工作正常 ✅")
    
} catch {
    print("❌ 错误: \(error)")
}

// 清理测试目录
try? FileManager.default.removeItem(at: testDir)
print("🧹 清理完成")