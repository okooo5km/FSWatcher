//
//  DirectoryWatcherTests.swift
//  FSWatcherTests
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import XCTest
import Combine
@testable import FSWatcher

final class DirectoryWatcherTests: XCTestCase {
    
    var testDirectory: URL!
    var watcher: DirectoryWatcher!
    
    override func setUpWithError() throws {
        // Create a temporary test directory
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("FSWatcherTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        // Create the watcher
        watcher = try DirectoryWatcher(url: testDirectory)
    }
    
    override func tearDownWithError() throws {
        // Stop the watcher
        watcher?.stop()
        watcher = nil
        
        // Clean up test directory
        if let testDirectory = testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
    }
    
    func testInitialization() throws {
        XCTAssertNotNil(watcher)
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testStartAndStop() throws {
        // Start watching
        watcher.start()
        XCTAssertTrue(watcher.isWatching)
        
        // Stop watching
        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testDirectoryChangeDetection() throws {
        let expectation = XCTestExpectation(description: "Directory change detected")
        
        watcher.onDirectoryChange = { url in
            XCTAssertEqual(url, self.testDirectory)
            expectation.fulfill()
        }
        
        watcher.start()
        
        // Create a file to trigger a change
        let testFile = testDirectory.appendingPathComponent("test.txt")
        try "Hello, World!".write(to: testFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testFileFiltering() throws {
        // Add a filter for text files only
        watcher.addFilter(.fileExtensions(["txt"]))
        
        let expectation = XCTestExpectation(description: "Filtered change detected")
        
        watcher.onFilteredChange = { urls in
            XCTAssertEqual(urls.count, 1)
            XCTAssertEqual(urls.first?.pathExtension, "txt")
            expectation.fulfill()
        }
        
        watcher.start()
        
        // Create files
        let textFile = testDirectory.appendingPathComponent("test.txt")
        let imageFile = testDirectory.appendingPathComponent("test.png")
        
        try "Text content".write(to: textFile, atomically: true, encoding: .utf8)
        try Data().write(to: imageFile) // Empty data for testing
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testIgnoreList() throws {
        let ignoredFile = testDirectory.appendingPathComponent("ignored.txt")
        watcher.addIgnoredFiles([ignoredFile])
        
        let expectation = XCTestExpectation(description: "Change detected")
        expectation.isInverted = true // We expect this NOT to be called
        
        watcher.onFilteredChange = { urls in
            // Should not include the ignored file
            XCTAssertFalse(urls.contains(ignoredFile))
            if urls.contains(ignoredFile) {
                expectation.fulfill()
            }
        }
        
        watcher.start()
        
        // Create the ignored file
        try "Ignored content".write(to: ignoredFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testPredictiveIgnore() throws {
        let predictor = FileTransformPredictor(rules: [
            FileTransformPredictor.TransformRule(
                inputPattern: ".*\\.txt$",
                outputTemplate: "{name}_processed.txt",
                formatChange: false
            )
        ])
        
        var config = DirectoryWatcher.Configuration()
        config.transformPredictor = predictor
        
        let watcher = try DirectoryWatcher(url: testDirectory, configuration: config)
        
        let expectation = XCTestExpectation(description: "Filtered change detected")
        
        watcher.onFilteredChange = { urls in
            // The predicted output file should be ignored
            let processedFile = self.testDirectory.appendingPathComponent("test_processed.txt")
            XCTAssertFalse(urls.contains(processedFile))
            expectation.fulfill()
        }
        
        watcher.start()
        
        // Create input file
        let inputFile = testDirectory.appendingPathComponent("test.txt")
        try "Input content".write(to: inputFile, atomically: true, encoding: .utf8)
        
        // Simulate processing - create the predicted output file
        let outputFile = testDirectory.appendingPathComponent("test_processed.txt")
        try "Processed content".write(to: outputFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testCombinePublisher() throws {
        
        var cancellables = Set<AnyCancellable>()
        let expectation = XCTestExpectation(description: "Publisher emitted value")
        
        watcher.directoryChangePublisher
            .sink { url in
                XCTAssertEqual(url, self.testDirectory)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        watcher.start()
        
        // Trigger a change
        let testFile = testDirectory.appendingPathComponent("test.txt")
        try "Content".write(to: testFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testAsyncStream() async throws {
        watcher.start()
        
        // Create a task to listen for changes
        let task = Task {
            for await url in watcher.directoryChanges {
                XCTAssertEqual(url, testDirectory)
                break // Exit after first change
            }
        }
        
        // Give the stream time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Trigger a change
        let testFile = testDirectory.appendingPathComponent("test.txt")
        try "Content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait for the task to complete
        await task.value
    }
    
    func testDebouncing() throws {
        var changeCount = 0
        let expectation = XCTestExpectation(description: "Debounced change")
        
        watcher.onDirectoryChange = { _ in
            changeCount += 1
            if changeCount == 1 {
                expectation.fulfill()
            }
        }
        
        watcher.start()
        
        // Create multiple files rapidly
        for i in 0..<5 {
            let file = testDirectory.appendingPathComponent("test\(i).txt")
            try "Content \(i)".write(to: file, atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 0.05) // Small delay between writes
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        // Due to debouncing, we should have received fewer events than files created
        XCTAssertLessThan(changeCount, 5)
    }
}