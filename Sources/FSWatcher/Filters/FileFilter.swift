//
//  FileFilter.swift
//  FSWatcher
//
//  Created by FSWatcher on 2025/08/13.
//

import Foundation
import UniformTypeIdentifiers

/// A filter for file system events
public struct FileFilter {
    private let predicate: (URL) -> Bool
    
    /// Initialize with a custom predicate
    /// - Parameter predicate: The predicate function
    public init(predicate: @escaping (URL) -> Bool) {
        self.predicate = predicate
    }
    
    // MARK: - Predefined Filters
    
    /// Filter by file extensions
    /// - Parameter extensions: The file extensions to match (case-insensitive)
    /// - Returns: A filter that matches files with the specified extensions
    public static func fileExtensions(_ extensions: [String]) -> FileFilter {
        FileFilter { url in
            extensions.contains(url.pathExtension.lowercased())
        }
    }
    
    /// Filter by UTTypes
    /// - Parameter types: The UTTypes to match
    /// - Returns: A filter that matches files conforming to the specified types
    @available(macOS 11.0, iOS 14.0, *)
    public static func utTypes(_ types: [UTType]) -> FileFilter {
        FileFilter { url in
            guard let fileUTI = UTType(filenameExtension: url.pathExtension) else { return false }
            return types.contains { type in
                fileUTI.conforms(to: type) || type.conforms(to: fileUTI)
            }
        }
    }
    
    /// Convenient filter for image files
    @available(macOS 11.0, iOS 14.0, *)
    public static var imageFiles: FileFilter {
        utTypes([.png, .jpeg, .webP, .heic, .heif, .tiff, .gif, .bmp, .ico, .icns])
    }
    
    /// Convenient filter for video files
    @available(macOS 11.0, iOS 14.0, *)
    public static var videoFiles: FileFilter {
        utTypes([.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi])
    }
    
    /// Convenient filter for audio files
    @available(macOS 11.0, iOS 14.0, *)
    public static var audioFiles: FileFilter {
        utTypes([.audio, .mp3, .mpeg4Audio, .wav, .aiff])
    }
    
    /// Convenient filter for document files
    @available(macOS 11.0, iOS 14.0, *)
    public static var documentFiles: FileFilter {
        utTypes([.pdf, .rtf, .plainText, .html, .xml, .yaml, .json])
    }
    
    /// Filter by file name pattern
    /// - Parameter pattern: The regular expression pattern to match
    /// - Returns: A filter that matches files with names matching the pattern
    public static func fileName(matching pattern: String) -> FileFilter {
        FileFilter { url in
            url.lastPathComponent.range(of: pattern, options: .regularExpression) != nil
        }
    }
    
    /// Filter by file size range
    /// - Parameter range: The size range in bytes
    /// - Returns: A filter that matches files within the specified size range
    public static func fileSize(_ range: ClosedRange<Int>) -> FileFilter {
        FileFilter { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return false
            }
            return range.contains(size)
        }
    }
    
    /// Filter by modification date
    /// - Parameter interval: The time interval from now (in seconds)
    /// - Returns: A filter that matches files modified within the specified interval
    public static func modifiedWithin(_ interval: TimeInterval) -> FileFilter {
        FileFilter { url in
            guard let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                return false
            }
            return Date().timeIntervalSince(modDate) <= interval
        }
    }
    
    /// Filter for directories only
    public static var directoriesOnly: FileFilter {
        FileFilter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
    
    /// Filter for regular files only
    public static var filesOnly: FileFilter {
        FileFilter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }
    
    /// Create a custom filter
    /// - Parameter predicate: The predicate function
    /// - Returns: A filter with the custom predicate
    public static func custom(_ predicate: @escaping (URL) -> Bool) -> FileFilter {
        FileFilter(predicate: predicate)
    }
    
    // MARK: - Filter Combinations
    
    /// Combine with another filter using AND logic
    /// - Parameter other: The other filter
    /// - Returns: A filter that matches when both filters match
    public func and(_ other: FileFilter) -> FileFilter {
        FileFilter { url in
            self.predicate(url) && other.predicate(url)
        }
    }
    
    /// Combine with another filter using OR logic
    /// - Parameter other: The other filter
    /// - Returns: A filter that matches when either filter matches
    public func or(_ other: FileFilter) -> FileFilter {
        FileFilter { url in
            self.predicate(url) || other.predicate(url)
        }
    }
    
    /// Negate the filter
    /// - Returns: A filter that matches when this filter doesn't match
    public func not() -> FileFilter {
        FileFilter { url in
            !self.predicate(url)
        }
    }
    
    // MARK: - Internal Methods
    
    /// Check if a URL matches this filter
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL matches the filter
    internal func matches(_ url: URL) -> Bool {
        predicate(url)
    }
}