//
//  FileSystemEvent.swift
//  FSWatcher
//
//  Created by FSWatcher on 2025/08/13.
//

import Foundation

/// Represents a file system event
public struct FileSystemEvent {
    /// The URL of the file or directory that triggered the event
    public let url: URL
    
    /// The type of event that occurred
    public let eventType: EventType
    
    /// The timestamp when the event occurred
    public let timestamp: Date
    
    /// Types of file system events
    public enum EventType {
        case created
        case modified
        case deleted
        case renamed
        case unknown
    }
    
    /// Initialize a new file system event
    /// - Parameters:
    ///   - url: The URL of the file or directory
    ///   - eventType: The type of event
    ///   - timestamp: The timestamp of the event (defaults to current time)
    public init(url: URL, eventType: EventType, timestamp: Date = Date()) {
        self.url = url
        self.eventType = eventType
        self.timestamp = timestamp
    }
}