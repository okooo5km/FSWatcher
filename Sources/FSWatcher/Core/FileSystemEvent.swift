//
//  FileSystemEvent.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation

/// Represents a file system event
public struct FileSystemEvent {
    /// The kind of item that triggered the event.
    public enum ItemKind: Equatable, Sendable {
        case file
        case directory
        case symbolicLink
        case unknown
    }

    /// The URL of the file or directory that triggered the event
    public let url: URL

    /// The type of event that occurred
    public let eventType: EventType

    /// The timestamp when the event occurred
    public let timestamp: Date

    /// The kind of item that triggered the event.
    public let itemKind: ItemKind

    /// True when the OS reported that the event stream may have lost detail
    /// and callers should rescan the reported URL.
    public let requiresRescan: Bool

    /// Platform-specific raw event flags, when available.
    public let rawFlags: UInt32

    /// Platform-specific event identifier, when available.
    public let eventID: UInt64?

    /// Types of file system events
    public enum EventType: Equatable, Sendable {
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
    ///   - itemKind: The kind of file-system item
    ///   - requiresRescan: Whether callers should rescan `url`
    ///   - rawFlags: Platform-specific raw flags
    ///   - eventID: Platform-specific event identifier
    public init(
        url: URL,
        eventType: EventType,
        timestamp: Date = Date(),
        itemKind: ItemKind = .unknown,
        requiresRescan: Bool = false,
        rawFlags: UInt32 = 0,
        eventID: UInt64? = nil
    ) {
        self.url = url
        self.eventType = eventType
        self.timestamp = timestamp
        self.itemKind = itemKind
        self.requiresRescan = requiresRescan
        self.rawFlags = rawFlags
        self.eventID = eventID
    }
}
