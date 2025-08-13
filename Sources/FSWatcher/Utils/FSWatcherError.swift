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
        }
    }
}