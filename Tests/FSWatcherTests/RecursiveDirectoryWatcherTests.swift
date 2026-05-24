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

    #if os(macOS)
        // MARK: - FSEvents backend

        func testFSEventsBackendBypassesDispatchSourceDirectoryCeiling() throws {
            for index in 0..<20 {
                let subdir = rootDir.appendingPathComponent("sub_\(index)")
                try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            }

            let options = RecursiveWatchOptions(maxDepth: 1, maxWatchedDirectories: 1, backend: .fsevents)
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration()
            )

            let errorsLock = NSLock()
            var limitErrors: [Int] = []
            watcher.onError = { error in
                if case .tooManyWatchers(let limit) = error {
                    errorsLock.lock()
                    limitErrors.append(limit)
                    errorsLock.unlock()
                }
            }

            let changedFile =
                rootDir
                .appendingPathComponent("sub_19")
                .appendingPathComponent("photo.jpg")
            let changeDetected = expectation(description: "FSEvents detects directory past DispatchSource ceiling")
            fulfillOnce(changeDetected) { fulfill in
                watcher.onDirectoryChange = { url in
                    if Self.sameFile(url, changedFile.deletingLastPathComponent()) {
                        fulfill()
                    }
                }
            }

            watcher.start()
            defer { watcher.stop() }

            XCTAssertTrue(watcher.isWatching)
            XCTAssertEqual(watcher.watchedDirectories, [rootDir])

            try writeJPEGStub(to: changedFile)
            wait(for: [changeDetected], timeout: 5.0)

            errorsLock.lock()
            XCTAssertTrue(limitErrors.isEmpty)
            errorsLock.unlock()
        }

        func testAutomaticBackendUsesFSEventsOnMacOSWhenSymlinksAreDisabled() throws {
            let subdir = rootDir.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

            let options = RecursiveWatchOptions(maxDepth: 1, maxWatchedDirectories: 1, backend: .automatic)
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration()
            )

            watcher.start()
            defer { watcher.stop() }

            XCTAssertTrue(watcher.isWatching)
            XCTAssertEqual(watcher.watchedDirectories, [rootDir])
        }

        func testAutomaticBackendFallsBackToDispatchSourceWhenFollowingSymlinks() throws {
            let subdir = rootDir.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

            let options = RecursiveWatchOptions(
                maxDepth: 1,
                followSymlinks: true,
                maxWatchedDirectories: 8,
                backend: .automatic
            )
            let watcher = try RecursiveDirectoryWatcher(url: rootDir, options: options)

            watcher.start()
            defer { watcher.stop() }

            XCTAssertTrue(watcher.isWatching)
            XCTAssertGreaterThanOrEqual(watcher.watchedDirectories.count, 2)
        }

        func testFSEventsBackendDetectsFilteredFileInDeepDirectory() throws {
            let deepDir =
                rootDir
                .appendingPathComponent("level1")
                .appendingPathComponent("level2")
            try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)

            let imageURL = deepDir.appendingPathComponent("photo.jpg")
            let options = RecursiveWatchOptions(maxDepth: 2, backend: .fsevents)
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration(filter: .fileExtensions(["jpg"]))
            )

            let filteredDetected = expectation(description: "FSEvents emits filtered deep image")
            fulfillOnce(filteredDetected) { fulfill in
                watcher.onFilteredChange = { urls in
                    if urls.contains(where: { Self.sameFile($0, imageURL) }) {
                        fulfill()
                    }
                }
            }

            watcher.start()
            defer { watcher.stop() }

            try writeJPEGStub(to: imageURL)
            wait(for: [filteredDetected], timeout: 5.0)
        }

        func testFSEventsBackendEmitsFileLevelEvent() throws {
            let deepDir =
                rootDir
                .appendingPathComponent("level1")
                .appendingPathComponent("level2")
            try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)

            let imageURL = deepDir.appendingPathComponent("file-event.jpg")
            let options = RecursiveWatchOptions(maxDepth: 2, backend: .fsevents)
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration(filter: .fileExtensions(["jpg"]))
            )

            let fileDetected = expectation(description: "FSEvents emits exact file event")
            fulfillOnce(fileDetected) { fulfill in
                watcher.onFileChange = { event in
                    if Self.sameFile(event.url, imageURL) {
                        XCTAssertEqual(event.itemKind, .file)
                        XCTAssertTrue([.created, .modified, .renamed, .unknown].contains(event.eventType))
                        XCTAssertFalse(event.requiresRescan)
                        XCTAssertNotNil(event.eventID)
                        fulfill()
                    }
                }
            }

            watcher.start()
            defer { watcher.stop() }

            try writeJPEGStub(to: imageURL)
            wait(for: [fileDetected], timeout: 5.0)
        }

        func testFSEventsFileLevelEventRespectsMaxDepth() throws {
            let allowedDir = rootDir.appendingPathComponent("level1")
            let blockedDir = allowedDir.appendingPathComponent("level2")
            try FileManager.default.createDirectory(at: blockedDir, withIntermediateDirectories: true)

            let allowedURL = allowedDir.appendingPathComponent("allowed.jpg")
            let blockedURL = blockedDir.appendingPathComponent("blocked.jpg")
            let options = RecursiveWatchOptions(maxDepth: 1, backend: .fsevents)
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration(filter: .fileExtensions(["jpg"]))
            )

            let allowedDetected = expectation(description: "depth 1 file event emitted")
            let blockedDetected = expectation(description: "depth 2 file event suppressed")
            blockedDetected.isInverted = true
            fulfillOnce(allowedDetected) { fulfill in
                watcher.onFileChange = { event in
                    if Self.sameFile(event.url, blockedURL) {
                        blockedDetected.fulfill()
                    }
                    if Self.sameFile(event.url, allowedURL) {
                        fulfill()
                    }
                }
            }

            watcher.start()
            defer { watcher.stop() }

            try writeJPEGStub(to: allowedURL)
            try writeJPEGStub(to: blockedURL)
            wait(for: [allowedDetected, blockedDetected], timeout: 5.0)
        }

        func testFSEventsBackendRespectsMaxDepth() throws {
            let deepDir =
                rootDir
                .appendingPathComponent("level1")
                .appendingPathComponent("level2")
            try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)

            let imageURL = deepDir.appendingPathComponent("too-deep.jpg")
            let options = RecursiveWatchOptions(maxDepth: 1, backend: .fsevents)
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration(filter: .fileExtensions(["jpg"]))
            )

            let filteredDetected = expectation(description: "too-deep image should not be emitted")
            filteredDetected.isInverted = true
            watcher.onFilteredChange = { urls in
                if urls.contains(where: { Self.sameFile($0, imageURL) }) {
                    filteredDetected.fulfill()
                }
            }

            watcher.start()
            defer { watcher.stop() }

            try writeJPEGStub(to: imageURL)
            wait(for: [filteredDetected], timeout: 1.5)
        }

        func testFSEventsBackendRespectsExcludePatterns() throws {
            let skippedDir = rootDir.appendingPathComponent("skip")
            let keptDir = rootDir.appendingPathComponent("keep")
            try FileManager.default.createDirectory(at: skippedDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: keptDir, withIntermediateDirectories: true)

            let skippedImage = skippedDir.appendingPathComponent("ignored.jpg")
            let keptImage = keptDir.appendingPathComponent("accepted.jpg")
            let options = RecursiveWatchOptions(
                maxDepth: 1,
                excludePatterns: ["skip"],
                backend: .fsevents
            )
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration(filter: .fileExtensions(["jpg"]))
            )

            let skippedDetected = expectation(description: "excluded image should not be emitted")
            skippedDetected.isInverted = true
            let keptDetected = expectation(description: "non-excluded image should be emitted")
            fulfillOnce(keptDetected) { fulfill in
                watcher.onFilteredChange = { urls in
                    if urls.contains(where: { Self.sameFile($0, skippedImage) }) {
                        skippedDetected.fulfill()
                    }
                    if urls.contains(where: { Self.sameFile($0, keptImage) }) {
                        fulfill()
                    }
                }
            }

            watcher.start()
            defer { watcher.stop() }

            try writeJPEGStub(to: skippedImage)
            try writeJPEGStub(to: keptImage)
            wait(for: [skippedDetected, keptDetected], timeout: 5.0)
        }

        func testFSEventsBackendDetectsRenameIntoWatchedTree() throws {
            let targetDir = rootDir.appendingPathComponent("drop")
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            let outsideDir =
                rootDir
                .deletingLastPathComponent()
                .appendingPathComponent("Outside_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outsideDir) }

            let sourceURL = outsideDir.appendingPathComponent("move-in.jpg")
            let targetURL = targetDir.appendingPathComponent("move-in.jpg")
            try writeJPEGStub(to: sourceURL)

            let options = RecursiveWatchOptions(maxDepth: 1, backend: .fsevents)
            let watcher = try RecursiveDirectoryWatcher(
                url: rootDir,
                options: options,
                configuration: fastConfiguration(filter: .fileExtensions(["jpg"]))
            )

            let filteredDetected = expectation(description: "FSEvents detects moved-in image")
            fulfillOnce(filteredDetected) { fulfill in
                watcher.onFilteredChange = { urls in
                    if urls.contains(where: { Self.sameFile($0, targetURL) }) {
                        fulfill()
                    }
                }
            }

            watcher.start()
            defer { watcher.stop() }

            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            wait(for: [filteredDetected], timeout: 5.0)
        }
    #endif

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

    private func fastConfiguration(filter: FileFilter? = nil) -> DirectoryWatcher.Configuration {
        var configuration = DirectoryWatcher.Configuration()
        configuration.debounceInterval = 0.1
        if let filter {
            configuration.filterChain.add(filter)
        }
        return configuration
    }

    private func writeJPEGStub(to url: URL) throws {
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL == rhs.resolvingSymlinksInPath().standardizedFileURL
    }

    private func fulfillOnce(_ expectation: XCTestExpectation, install: (@escaping () -> Void) -> Void) {
        let lock = NSLock()
        var didFulfill = false
        install {
            lock.lock()
            defer { lock.unlock() }
            guard !didFulfill else { return }
            didFulfill = true
            expectation.fulfill()
        }
    }
}
