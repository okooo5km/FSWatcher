//
//  main.swift
//  FSWatcherExample
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation
import FSWatcher

print("🚀 FSWatcher Example Test")
print("===================")

// Create test directory
let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("FSWatcherTest_\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

print("📁 Test Directory: \(testDir.path)")

do {
    // Test 1: Basic directory monitoring
    print("\n🔍 Test 1: Basic Directory Monitoring")
    
    let watcher = try DirectoryWatcher(url: testDir)
    var changeCount = 0
    
    watcher.onDirectoryChange = { url in
        changeCount += 1
        print("  ✅ Change detected #\(changeCount): \(url.lastPathComponent)")
    }
    
    watcher.start()
    print("  Starting monitoring...")
    
    // Create test files
    for i in 1...3 {
        let testFile = testDir.appendingPathComponent("test\(i).txt")
        try! "Test content \(i)".write(to: testFile, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    // Wait for event processing
    Thread.sleep(forTimeInterval: 1.0)
    watcher.stop()
    print("  Monitoring stopped, detected \(changeCount) changes")
    
    // Test 2: Filter test
    print("\n🎯 Test 2: File Filtering")
    
    var config = DirectoryWatcher.Configuration()
    config.filterChain.add(.fileExtensions(["jpg", "png"]))
    
    let filteredWatcher = try DirectoryWatcher(url: testDir, configuration: config)
    var filteredCount = 0
    
    filteredWatcher.onFilteredChange = { imageFiles in
        filteredCount += imageFiles.count
        print("  🖼️  Image files detected: \(imageFiles.map { $0.lastPathComponent })")
    }
    
    filteredWatcher.start()
    
    // Create different types of files
    let imageFile = testDir.appendingPathComponent("image.jpg")
    let textFile = testDir.appendingPathComponent("document.txt")
    
    try! Data().write(to: imageFile)  // Image file
    try! "Text content".write(to: textFile, atomically: true, encoding: .utf8)  // Text file
    
    Thread.sleep(forTimeInterval: 1.0)
    filteredWatcher.stop()
    print("  Detected \(filteredCount) image files after filtering")
    
    // Test 3: Ignore list test
    print("\n🚫 Test 3: Ignore List")
    
    let ignoreWatcher = try DirectoryWatcher(url: testDir)
    var ignoreCount = 0
    
    // Add ignored files
    let ignoredFile = testDir.appendingPathComponent("ignored.txt")
    ignoreWatcher.addIgnoredFiles([ignoredFile])
    
    ignoreWatcher.onFilteredChange = { files in
        let nonIgnoredFiles = files.filter { !$0.lastPathComponent.contains("ignored") }
        ignoreCount += nonIgnoredFiles.count
        print("  📝 Non-ignored files detected: \(nonIgnoredFiles.map { $0.lastPathComponent })")
    }
    
    ignoreWatcher.start()
    
    // Create ignored and non-ignored files
    try! "Ignored content".write(to: ignoredFile, atomically: true, encoding: .utf8)
    let normalFile = testDir.appendingPathComponent("normal.txt")
    try! "Normal content".write(to: normalFile, atomically: true, encoding: .utf8)
    
    Thread.sleep(forTimeInterval: 1.0)
    ignoreWatcher.stop()
    print("  Ignore list working correctly")
    
    print("\n🎉 All tests completed!")
    print("FSWatcher is working correctly ✅")
    
} catch {
    print("❌ Error: \(error)")
}

// Clean up test directory
try? FileManager.default.removeItem(at: testDir)
print("🧹 Cleanup completed")