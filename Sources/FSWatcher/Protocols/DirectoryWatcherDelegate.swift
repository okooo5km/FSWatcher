//
//  DirectoryWatcherDelegate.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation

/// Protocol for receiving directory change notifications
public protocol DirectoryWatcherDelegate: AnyObject {
    /// Called when a directory change is detected
    /// - Parameter url: The URL of the directory that changed
    func directoryDidChange(at url: URL)

    /// Called when a directory change is detected with detailed event information
    /// - Parameter event: The file system event that occurred
    func directoryDidChange(with event: FileSystemEvent)

    /// Called when a file-level change is detected.
    /// - Parameter event: The file system event that occurred
    func fileDidChange(with event: FileSystemEvent)
}

// Provide default implementation
extension DirectoryWatcherDelegate {
    public func directoryDidChange(with event: FileSystemEvent) {
        directoryDidChange(at: event.url)
    }

    public func fileDidChange(with event: FileSystemEvent) {}
}
