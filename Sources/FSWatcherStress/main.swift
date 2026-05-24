//
//  main.swift
//  FSWatcherStress
//
//  Created by okooo5km(十里) on 2026/05/24.
//

import FSWatcher
import Foundation

#if canImport(Darwin)
    import Darwin
#endif

struct StressOptions {
    var root: URL?
    var directoryCount = 1_000
    var filesPerDirectory = 0
    var maxDepth = 2
    var maxWatchedDirectories = 256
    var backend: RecursiveWatchBackend = .fsevents
    var keepTree = false
    var timeout: TimeInterval = 10
}

@main
enum FSWatcherStress {
    static func main() async throws {
        let options = try parseOptions()
        let fileManager = FileManager.default
        let root =
            options.root
            ?? fileManager.temporaryDirectory
            .appendingPathComponent("FSWatcherStress_\(UUID().uuidString)")

        if fileManager.fileExists(atPath: root.path), !options.keepTree {
            try fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        if options.root == nil || isDirectoryEmpty(root) {
            print("Preparing tree at \(root.path)")
            try buildTree(
                root: root,
                directoryCount: options.directoryCount,
                filesPerDirectory: options.filesPerDirectory
            )
        } else {
            print("Using existing tree at \(root.path)")
        }

        let eventDirectory = directoryURL(root: root, index: max(0, options.directoryCount - 1))
        try fileManager.createDirectory(at: eventDirectory, withIntermediateDirectories: true)
        let eventFile = eventDirectory.appendingPathComponent("zz_event_\(UUID().uuidString).jpg")

        var configuration = DirectoryWatcher.Configuration()
        configuration.debounceInterval = 0.1
        configuration.filterChain.add(.fileExtensions(["jpg"]))

        let watchOptions = RecursiveWatchOptions(
            maxDepth: options.maxDepth,
            followSymlinks: false,
            excludePatterns: [],
            maxWatchedDirectories: options.maxWatchedDirectories,
            backend: options.backend
        )

        let watcher = try RecursiveDirectoryWatcher(url: root, options: watchOptions, configuration: configuration)
        let state = StressState()

        watcher.onFilteredChange = { urls in
            guard urls.contains(where: { sameFile($0, eventFile) }) else { return }
            state.markMatched()
        }
        watcher.onDirectoryChange = { url in
            guard sameFile(url, eventDirectory) else { return }
            state.markMatched()
        }
        watcher.onError = { error in
            state.record(error.localizedDescription)
        }

        let fdBefore = fileDescriptorCount()
        let startTime = Date()
        await watcher.startAsync()
        let startElapsed = Date().timeIntervalSince(startTime)
        let fdAfterStart = fileDescriptorCount()

        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: eventFile)
        let signaled = await state.waitForMatch(timeout: options.timeout)
        try await Task.sleep(nanoseconds: 200_000_000)

        let watchedDirectories = watcher.watchedDirectories.count
        let isWatching = watcher.isWatching
        watcher.stop()
        let fdAfterStop = fileDescriptorCount()

        let snapshot = state.snapshot()
        let finalMatched = snapshot.matched || signaled
        let finalErrors = snapshot.errors

        print("backend=\(options.backend)")
        print("root=\(root.path)")
        print("directoryCount=\(options.directoryCount)")
        print("filesPerDirectory=\(options.filesPerDirectory)")
        print("maxDepth=\(options.maxDepth)")
        print("maxWatchedDirectories=\(options.maxWatchedDirectories)")
        print(String(format: "startElapsed=%.3fs", startElapsed))
        print("watchedDirectories=\(watchedDirectories)")
        print("isWatchingAfterStart=\(isWatching)")
        print("fdBefore=\(fdBefore)")
        print("fdAfterStart=\(fdAfterStart)")
        print("fdDelta=\(fdAfterStart - fdBefore)")
        print("fdAfterStop=\(fdAfterStop)")
        print("eventDirectory=\(eventDirectory.path)")
        print("eventMatched=\(finalMatched)")
        if !finalErrors.isEmpty {
            print("errors=\(finalErrors)")
        }

        if !options.keepTree {
            try? fileManager.removeItem(at: root)
        }

        if !finalMatched {
            fputs("error=Watcher did not report the event file within \(options.timeout)s\n", stderr)
            exit(1)
        }
    }

    private static func parseOptions() throws -> StressOptions {
        var options = StressOptions()
        var arguments = Array(CommandLine.arguments.dropFirst())

        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--root":
                options.root = URL(fileURLWithPath: try takeValue(for: argument, from: &arguments))
            case "--dirs":
                options.directoryCount = try intValue(argument, &arguments)
            case "--files-per-dir":
                options.filesPerDirectory = try intValue(argument, &arguments)
            case "--max-depth":
                options.maxDepth = try intValue(argument, &arguments)
            case "--max-watchers":
                options.maxWatchedDirectories = try intValue(argument, &arguments)
            case "--backend":
                options.backend = try backendValue(try takeValue(for: argument, from: &arguments))
            case "--timeout":
                options.timeout = try doubleValue(argument, &arguments)
            case "--keep":
                options.keepTree = true
            case "--help", "-h":
                printUsageAndExit()
            default:
                throw NSError(
                    domain: "FSWatcherStress",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown argument: \(argument)"]
                )
            }
        }

        guard options.directoryCount > 0 else {
            throw NSError(
                domain: "FSWatcherStress",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "--dirs must be greater than 0"]
            )
        }
        guard options.filesPerDirectory >= 0 else {
            throw NSError(
                domain: "FSWatcherStress",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "--files-per-dir must be 0 or greater"]
            )
        }
        return options
    }

    private static func buildTree(root: URL, directoryCount: Int, filesPerDirectory: Int) throws {
        for index in 0..<directoryCount {
            let directory = directoryURL(root: root, index: index)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard filesPerDirectory > 0 else { continue }

            for fileIndex in 0..<filesPerDirectory {
                let file = directory.appendingPathComponent(String(format: "seed_%05d.jpg", fileIndex))
                if !FileManager.default.fileExists(atPath: file.path) {
                    try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: file)
                }
            }
        }
    }

    private static func directoryURL(root: URL, index: Int) -> URL {
        root
            .appendingPathComponent(String(format: "group_%04d", index / 1_000))
            .appendingPathComponent(String(format: "dir_%06d", index))
    }

    private static func isDirectoryEmpty(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty) ?? true
    }

    private static func fileDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL == rhs.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func takeValue(for argument: String, from arguments: inout [String]) throws -> String {
        guard !arguments.isEmpty else {
            throw NSError(
                domain: "FSWatcherStress",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing value for \(argument)"]
            )
        }
        return arguments.removeFirst()
    }

    private static func intValue(_ argument: String, _ arguments: inout [String]) throws -> Int {
        let rawValue = try takeValue(for: argument, from: &arguments)
        guard let value = Int(rawValue) else {
            throw NSError(
                domain: "FSWatcherStress",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(argument) requires an integer"]
            )
        }
        return value
    }

    private static func doubleValue(_ argument: String, _ arguments: inout [String]) throws -> Double {
        let rawValue = try takeValue(for: argument, from: &arguments)
        guard let value = Double(rawValue) else {
            throw NSError(
                domain: "FSWatcherStress",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(argument) requires a number"]
            )
        }
        return value
    }

    private static func backendValue(_ rawValue: String) throws -> RecursiveWatchBackend {
        switch rawValue {
        case "automatic":
            return .automatic
        case "dispatch", "dispatchSource":
            return .dispatchSource
        case "fsevents":
            return .fsevents
        default:
            throw NSError(
                domain: "FSWatcherStress",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown backend: \(rawValue)"]
            )
        }
    }

    private static func printUsageAndExit() -> Never {
        print(
            """
            Usage:
              swift run FSWatcherStress [options]

            Options:
              --root PATH            Existing or new test root
              --dirs N               Leaf directory count, default 1000
              --files-per-dir N      Seed JPG files per leaf directory, default 0
              --backend NAME         fsevents, dispatch, or automatic, default fsevents
              --max-depth N          Recursive watch depth, default 2
              --max-watchers N       DispatchSource directory ceiling, default 256
              --timeout SECONDS      Event wait timeout, default 10
              --keep                 Keep the generated tree
            """)
        exit(0)
    }
}

private final class StressState: @unchecked Sendable {
    private let lock = NSLock()
    private var matched = false
    private var errors: [String] = []
    private var continuation: CheckedContinuation<Bool, Never>?

    func markMatched() {
        lock.lock()
        matched = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: true)
    }

    func record(_ error: String) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }

    func waitForMatch(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if matched {
                lock.unlock()
                continuation.resume(returning: true)
                return
            }

            self.continuation = continuation
            lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resolveTimeout()
            }
        }
    }

    func snapshot() -> (matched: Bool, errors: [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (matched, errors)
    }

    private func resolveTimeout() {
        lock.lock()
        guard !matched, let continuation else {
            lock.unlock()
            return
        }

        self.continuation = nil
        lock.unlock()

        continuation.resume(returning: false)
    }
}
