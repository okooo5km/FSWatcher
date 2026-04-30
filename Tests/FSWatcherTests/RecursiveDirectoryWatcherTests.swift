//
//  RecursiveDirectoryWatcherTests.swift
//  FSWatcherTests
//
//  Created by okooo5km(十里) on 2026/04/30.
//

import XCTest
@testable import FSWatcher

final class RecursiveDirectoryWatcherTests: XCTestCase {

    var rootDir: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        rootDir = tempDir.appendingPathComponent("RecursiveTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootDir = rootDir {
            try? FileManager.default.removeItem(at: rootDir)
        }
    }

    // MARK: - maxWatchedDirectories ceiling

    func testTooManyWatchersStopsScanAndReportsOnce() throws {
        // Twenty siblings at depth 1, ceiling = 5 → only 5 watchers should
        // come up and the limit error must be reported exactly once.
        for i in 0..<20 {
            let sub = rootDir.appendingPathComponent("sub_\(i)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }

        var options = RecursiveWatchOptions()
        options.maxWatchedDirectories = 5
        let watcher = try RecursiveDirectoryWatcher(url: rootDir, options: options)

        let errorsLock = NSLock()
        var errors: [FSWatcherError] = []
        watcher.onError = { error in
            errorsLock.lock()
            errors.append(error)
            errorsLock.unlock()
        }

        watcher.start()
        defer { watcher.stop() }

        XCTAssertLessThanOrEqual(watcher.watchedDirectories.count, 5)

        errorsLock.lock()
        let limitErrors = errors.compactMap { error -> Int? in
            if case .tooManyWatchers(let limit) = error { return limit }
            return nil
        }
        errorsLock.unlock()
        XCTAssertEqual(limitErrors, [5], "tooManyWatchers should fire exactly once with the configured limit")
    }

    // MARK: - Async start API

    func testStartOnQueueReturnsImmediately() throws {
        for i in 0..<50 {
            let sub = rootDir.appendingPathComponent("d_\(i)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }

        let watcher = try RecursiveDirectoryWatcher(url: rootDir)
        let beforeCall = Date()
        watcher.start(on: .global(qos: .utility))
        let elapsed = Date().timeIntervalSince(beforeCall)
        defer { watcher.stop() }

        XCTAssertLessThan(elapsed, 0.1, "start(on:) must not block the caller")

        let scanned = expectation(description: "async scan completes")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
            scanned.fulfill()
        }
        wait(for: [scanned], timeout: 3.0)

        XCTAssertTrue(watcher.isWatching)
        XCTAssertGreaterThanOrEqual(watcher.watchedDirectories.count, 50, "All 50 subdirs should eventually be watched")
    }

    func testStartAsyncAwaitsScanCompletion() async throws {
        for i in 0..<10 {
            let sub = rootDir.appendingPathComponent("d_\(i)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }

        let watcher = try RecursiveDirectoryWatcher(url: rootDir)
        await watcher.startAsync()
        defer { watcher.stop() }

        XCTAssertTrue(watcher.isWatching)
        // root + 10 subdirs
        XCTAssertGreaterThanOrEqual(watcher.watchedDirectories.count, 11)
    }

    // MARK: - Backward compatibility

    func testBackwardCompatibleSyncStart() throws {
        let watcher = try RecursiveDirectoryWatcher(url: rootDir)
        watcher.start()
        defer { watcher.stop() }

        XCTAssertTrue(watcher.isWatching)
        XCTAssertEqual(watcher.watchedDirectories.count, 1, "Empty root should produce exactly one watcher")

        let changeDetected = expectation(description: "directory change emitted")
        watcher.onDirectoryChange = { _ in changeDetected.fulfill() }

        let testFile = rootDir.appendingPathComponent("hello.txt")
        try "hello".write(to: testFile, atomically: true, encoding: .utf8)

        wait(for: [changeDetected], timeout: 3.0)
    }

    // MARK: - Recursive stability

    func testDeepAndWideRecursiveStability() throws {
        // 4 levels x 4 children = 4 + 16 + 64 + 256 = 340 dirs.
        // Stays under the default ceiling and exercises the iterative stack.
        try buildTree(at: rootDir, depth: 4, breadth: 4, currentDepth: 0)

        var options = RecursiveWatchOptions()
        options.maxWatchedDirectories = 1024
        let watcher = try RecursiveDirectoryWatcher(url: rootDir, options: options)
        watcher.start()
        defer { watcher.stop() }

        XCTAssertTrue(watcher.isWatching)
        // root + 340 subdirs = 341
        XCTAssertGreaterThanOrEqual(watcher.watchedDirectories.count, 341)
    }

    // MARK: - Error description sanity

    func testFailedToWatchErrorDescription() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent")
        let underlying = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let error = FSWatcherError.failedToWatch(url, underlying: underlying)
        XCTAssertTrue(error.errorDescription?.contains("boom") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("/tmp/nonexistent") ?? false)
    }

    func testTooManyWatchersErrorDescription() {
        let error = FSWatcherError.tooManyWatchers(limit: 256)
        XCTAssertTrue(error.errorDescription?.contains("256") ?? false)
    }

    // MARK: - Helpers

    private func buildTree(at parent: URL, depth: Int, breadth: Int, currentDepth: Int) throws {
        if currentDepth >= depth { return }
        for i in 0..<breadth {
            let sub = parent.appendingPathComponent("d\(currentDepth)_\(i)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try buildTree(at: sub, depth: depth, breadth: breadth, currentDepth: currentDepth + 1)
        }
    }
}
