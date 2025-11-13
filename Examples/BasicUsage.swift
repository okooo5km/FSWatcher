//
//  BasicUsage.swift
//  FSWatcher Examples
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation
import FSWatcher

// MARK: - Basic Directory Watching

func basicWatchingExample() {
    do {
        // Create a watcher for Documents directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watcher = try DirectoryWatcher(url: documentsURL)
        
        // Set up event handler
        watcher.onDirectoryChange = { url in
            print("Directory changed: \(url.path)")
        }
        
        // Start watching
        watcher.start()
        print("Started watching \(documentsURL.path)")
        
        // Keep the program running
        RunLoop.main.run()
        
    } catch {
        print("Error: \(error)")
    }
}

// MARK: - Filtered Watching

func filteredWatchingExample() {
    do {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        
        // Configure with filters
        var config = DirectoryWatcher.Configuration()
        config.filterChain.add(.imageFiles) // Only watch image files
        config.filterChain.add(.fileSize(1024...)) // At least 1KB
        
        let watcher = try DirectoryWatcher(url: downloadsURL, configuration: config)
        
        // Handle filtered changes
        watcher.onFilteredChange = { imageFiles in
            print("New images detected:")
            for file in imageFiles {
                print("  - \(file.lastPathComponent)")
            }
        }
        
        watcher.start()
        print("Watching for images in \(downloadsURL.path)")
        
        RunLoop.main.run()
        
    } catch {
        print("Error: \(error)")
    }
}

// MARK: - Multiple Directory Watching

func multiDirectoryExample() {
    let multiWatcher = MultiDirectoryWatcher()
    
    multiWatcher.onDirectoryChange = { url in
        print("Change detected in: \(url.path)")
    }
    
    multiWatcher.onError = { error in
        print("Error: \(error)")
    }
    
    // Watch multiple directories
    let directories = [
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!,
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    ].compactMap { $0 }
    
    multiWatcher.startWatching(directories: directories)
    
    print("Watching \(directories.count) directories")
    for dir in directories {
        print("  - \(dir.path)")
    }
    
    RunLoop.main.run()
}

// MARK: - Recursive Watching

func recursiveWatchingExample() {
    do {
        let projectURL = URL(fileURLWithPath: "/Users/username/MyProject")
        
        // Configure recursive options
        var options = RecursiveWatchOptions()
        options.maxDepth = 5
        options.excludePatterns = ["node_modules", ".git", "*.tmp", ".DS_Store"]
        options.followSymlinks = false
        
        let recursiveWatcher = try RecursiveDirectoryWatcher(
            url: projectURL,
            options: options
        )
        
        // Add filter for source files
        recursiveWatcher.addFilter(.fileExtensions(["swift", "m", "h"]))
        
        recursiveWatcher.onFilteredChange = { changedFiles in
            print("Source files changed:")
            for file in changedFiles {
                print("  - \(file.path)")
            }
        }
        
        recursiveWatcher.start()
        print("Recursively watching \(projectURL.path)")
        
        RunLoop.main.run()
        
    } catch {
        print("Error: \(error)")
    }
}

// MARK: - Multiple Recursive Directories

func multiRecursiveWatchingExample() {
    // Configure recursive options
    var options = RecursiveWatchOptions()
    options.maxDepth = 3
    options.excludePatterns = [".git", "node_modules", "*.tmp", ".DS_Store"]
    options.followSymlinks = false
    
    let multiRecursiveWatcher = MultiRecursiveDirectoryWatcher(options: options)
    
    multiRecursiveWatcher.onDirectoryChange = { url in
        print("Change detected: \(url.path)")
    }
    
    multiRecursiveWatcher.onFilteredChange = { files in
        print("Filtered files changed:")
        for file in files {
            print("  - \(file.path)")
        }
    }
    
    multiRecursiveWatcher.onError = { error in
        print("Error: \(error)")
    }
    
    // Watch multiple project directories recursively
    let projectDirectories = [
        URL(fileURLWithPath: "/Users/username/Project1"),
        URL(fileURLWithPath: "/Users/username/Project2"),
        URL(fileURLWithPath: "/Users/username/Project3")
    ]
    
    multiRecursiveWatcher.startWatching(directories: projectDirectories)
    
    print("Recursively watching \(projectDirectories.count) directories:")
    for dir in projectDirectories {
        print("  - \(dir.path)")
    }
    
    // Add filter for all watchers
    multiRecursiveWatcher.addFilter(.fileExtensions(["swift", "js", "ts"]))
    
    RunLoop.main.run()
}

// MARK: - Using with Combine

import Combine

func combineExample() {
    var cancellables = Set<AnyCancellable>()
    
    do {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watcher = try DirectoryWatcher(url: documentsURL)
        
        // Use Combine publisher
        watcher.directoryChangePublisher
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { url in
                print("Debounced change: \(url.path)")
            }
            .store(in: &cancellables)
        
        watcher.start()
        print("Watching with Combine: \(documentsURL.path)")
        
        RunLoop.main.run()
        
    } catch {
        print("Error: \(error)")
    }
}

// MARK: - Using with Swift Concurrency

@available(macOS 10.15, iOS 13.0, *)
func asyncExample() async {
    do {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watcher = try DirectoryWatcher(url: documentsURL)
        
        watcher.start()
        print("Async watching: \(documentsURL.path)")
        
        // Process changes asynchronously
        for await url in watcher.directoryChanges {
            print("Async change detected: \(url.path)")
            
            // Process the change
            await processChange(at: url)
        }
        
    } catch {
        print("Error: \(error)")
    }
}

@available(macOS 10.15, iOS 13.0, *)
func processChange(at url: URL) async {
    // Simulate async processing
    print("Processing change at \(url.path)...")
    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    print("Processing complete")
}

// MARK: - With Delegate Pattern

class WatcherDelegate: DirectoryWatcherDelegate {
    func directoryDidChange(at url: URL) {
        print("Delegate: Directory changed at \(url.path)")
    }
    
    func directoryDidChange(with event: FileSystemEvent) {
        print("Delegate: Event \(event.eventType) at \(event.url.path)")
    }
}

func delegateExample() {
    do {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watcher = try DirectoryWatcher(url: documentsURL)
        
        let delegate = WatcherDelegate()
        watcher.delegate = delegate
        
        watcher.start()
        print("Watching with delegate: \(documentsURL.path)")
        
        RunLoop.main.run()
        
    } catch {
        print("Error: \(error)")
    }
}

// MARK: - Main

print("FSWatcher Examples")
print("==================")
print("1. Basic watching")
print("2. Filtered watching")
print("3. Multi-directory watching")
print("4. Recursive watching")
print("5. Multi-recursive watching")
print("6. Combine integration")
print("7. Swift Concurrency")
print("8. Delegate pattern")
print("\nSelect an example (1-8):")

if let input = readLine(), let choice = Int(input) {
    switch choice {
    case 1:
        basicWatchingExample()
    case 2:
        filteredWatchingExample()
    case 3:
        multiDirectoryExample()
    case 4:
        recursiveWatchingExample()
    case 5:
        multiRecursiveWatchingExample()
    case 6:
        combineExample()
    case 7:
        if #available(macOS 10.15, iOS 13.0, *) {
            Task {
                await asyncExample()
            }
            RunLoop.main.run()
        } else {
            print("Swift Concurrency requires macOS 10.15+ or iOS 13.0+")
        }
    case 8:
        delegateExample()
    default:
        print("Invalid choice")
    }
} else {
    print("Invalid input")
}