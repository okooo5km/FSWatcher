//
//  URL+Extensions.swift
//  FSWatcher
//
//  Created by FSWatcher on 2025/08/13.
//

import Foundation

public extension URL {
    
    /// Check if the URL represents a directory
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: self.path, isDirectory: &isDir) && isDir.boolValue
    }
    
    /// Check if the URL represents a regular file
    var isRegularFile: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: self.path, isDirectory: &isDir) && !isDir.boolValue
    }
    
    /// Check if the file exists
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: self.path)
    }
    
    /// Get the file size in bytes
    var fileSize: Int? {
        try? resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
    
    /// Get the file modification date
    var modificationDate: Date? {
        try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    
    /// Get the file creation date
    var creationDate: Date? {
        try? resourceValues(forKeys: [.creationDateKey]).creationDate
    }
    
    /// Check if the URL is a symbolic link
    var isSymbolicLink: Bool {
        (try? resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }
    
    /// Check if the URL is hidden
    var isHidden: Bool {
        (try? resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
    }
    
    /// Get all subdirectories
    func subdirectories(includingHidden: Bool = false) -> [URL] {
        guard isDirectory else { return [] }
        
        do {
            let options: FileManager.DirectoryEnumerationOptions = includingHidden ? [] : [.skipsHiddenFiles]
            let contents = try FileManager.default.contentsOfDirectory(
                at: self,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: options
            )
            
            return contents.filter { $0.isDirectory }
        } catch {
            return []
        }
    }
    
    /// Get all files (non-directories)
    func files(includingHidden: Bool = false) -> [URL] {
        guard isDirectory else { return [] }
        
        do {
            let options: FileManager.DirectoryEnumerationOptions = includingHidden ? [] : [.skipsHiddenFiles]
            let contents = try FileManager.default.contentsOfDirectory(
                at: self,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: options
            )
            
            return contents.filter { $0.isRegularFile }
        } catch {
            return []
        }
    }
    
    /// Get all contents (files and directories)
    func contents(includingHidden: Bool = false) -> [URL] {
        guard isDirectory else { return [] }
        
        do {
            let options: FileManager.DirectoryEnumerationOptions = includingHidden ? [] : [.skipsHiddenFiles]
            return try FileManager.default.contentsOfDirectory(
                at: self,
                includingPropertiesForKeys: nil,
                options: options
            )
        } catch {
            return []
        }
    }
}