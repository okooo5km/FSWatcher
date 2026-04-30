//
//  FSWatcherError.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation

/// Errors that can occur during file system watching
public enum FSWatcherError: Error, LocalizedError {
    /// Cannot open the specified directory
    case cannotOpenDirectory(URL)

    /// Insufficient permissions to watch the directory
    case insufficientPermissions(URL)

    /// Directory not found at the specified path
    case directoryNotFound(URL)

    /// System resources unavailable for creating watcher
    case systemResourcesUnavailable

    /// Invalid configuration provided
    case invalidConfiguration(String)

    /// Recursive watcher hit the configured `maxWatchedDirectories` ceiling.
    /// Further subdirectories below this point are not being watched. The
    /// associated value is the active limit.
    case tooManyWatchers(limit: Int)

    /// A single directory failed to be watched while the recursive watcher was
    /// scanning. The associated underlying error explains why; the watcher
    /// continues with the rest of the tree.
    case failedToWatch(URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenDirectory(let url):
            return "Cannot open directory at path: \(url.path)"
        case .insufficientPermissions(let url):
            return "Insufficient permissions to watch directory: \(url.path)"
        case .directoryNotFound(let url):
            return "Directory not found at path: \(url.path)"
        case .systemResourcesUnavailable:
            return "System resources are unavailable for file system watching"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .tooManyWatchers(let limit):
            return "Reached the maximum number of watched directories (\(limit)). Additional subdirectories are not being watched."
        case .failedToWatch(let url, let underlying):
            return "Failed to watch directory \(url.path): \(underlying.localizedDescription)"
        }
    }
}