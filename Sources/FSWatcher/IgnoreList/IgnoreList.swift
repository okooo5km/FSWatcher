//
//  IgnoreList.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation

/// Manages a list of files to ignore during file system watching
public class IgnoreList {
    private var ignoredFiles: Set<URL> = []
    private var predictiveIgnores: Set<URL> = []
    private var ignorePatterns: [String] = []
    private let queue = DispatchQueue(label: "com.fswatcher.ignorelist", attributes: .concurrent)
    
    /// Initialize an empty ignore list
    public init() {}
    
    /// Initialize with initial ignored files
    /// - Parameter ignoredFiles: The initial files to ignore
    public init(ignoredFiles: [URL]) {
        self.ignoredFiles = Set(ignoredFiles)
    }
    
    // MARK: - Managing Ignored Files
    
    /// Add files to the ignore list
    /// - Parameter urls: The URLs to ignore
    public func addIgnored(_ urls: [URL]) {
        queue.async(flags: .barrier) {
            self.ignoredFiles.formUnion(urls)
        }
    }
    
    /// Add a single file to the ignore list
    /// - Parameter url: The URL to ignore
    public func addIgnored(_ url: URL) {
        addIgnored([url])
    }
    
    /// Remove files from the ignore list
    /// - Parameter urls: The URLs to stop ignoring
    public func removeIgnored(_ urls: [URL]) {
        queue.async(flags: .barrier) {
            self.ignoredFiles.subtract(urls)
        }
    }
    
    /// Remove a single file from the ignore list
    /// - Parameter url: The URL to stop ignoring
    public func removeIgnored(_ url: URL) {
        removeIgnored([url])
    }
    
    // MARK: - Predictive Ignoring
    
    /// Add files for predictive ignoring (files that will be created)
    /// - Parameter urls: The URLs to predictively ignore
    public func addPredictiveIgnore(_ urls: [URL]) {
        queue.async(flags: .barrier) {
            self.predictiveIgnores.formUnion(urls)
        }
    }
    
    /// Add a single file for predictive ignoring
    /// - Parameter url: The URL to predictively ignore
    public func addPredictiveIgnore(_ url: URL) {
        addPredictiveIgnore([url])
    }
    
    /// Remove files from predictive ignore list
    /// - Parameter urls: The URLs to stop predictively ignoring
    public func removePredictiveIgnore(_ urls: [URL]) {
        queue.async(flags: .barrier) {
            self.predictiveIgnores.subtract(urls)
        }
    }
    
    // MARK: - Pattern-based Ignoring
    
    /// Add a glob pattern to ignore
    /// - Parameter pattern: The glob pattern (e.g., "*.tmp", "node_modules")
    public func addIgnorePattern(_ pattern: String) {
        queue.async(flags: .barrier) {
            self.ignorePatterns.append(pattern)
        }
    }
    
    /// Add multiple glob patterns to ignore
    /// - Parameter patterns: The glob patterns to add
    public func addIgnorePatterns(_ patterns: [String]) {
        queue.async(flags: .barrier) {
            self.ignorePatterns.append(contentsOf: patterns)
        }
    }
    
    /// Remove a glob pattern from the ignore list
    /// - Parameter pattern: The pattern to remove
    public func removeIgnorePattern(_ pattern: String) {
        queue.async(flags: .barrier) {
            self.ignorePatterns.removeAll { $0 == pattern }
        }
    }
    
    // MARK: - Checking Ignore Status
    
    /// Check if a file should be ignored
    /// - Parameter url: The URL to check
    /// - Returns: true if the file should be ignored
    public func shouldIgnore(_ url: URL) -> Bool {
        queue.sync {
            // Check direct ignores
            if ignoredFiles.contains(url) || predictiveIgnores.contains(url) {
                return true
            }
            
            // Check patterns
            let fileName = url.lastPathComponent
            for pattern in ignorePatterns {
                if matchesGlobPattern(fileName: fileName, pattern: pattern) {
                    return true
                }
            }
            
            return false
        }
    }
    
    // MARK: - Maintenance
    
    /// Clean up non-existent files from the ignore lists
    public func cleanup() {
        queue.async(flags: .barrier) {
            // Remove files that no longer exist
            self.ignoredFiles = self.ignoredFiles.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            
            // Predictive ignores might not exist yet, so we keep them for a while
            // You might want to add timestamp tracking for more sophisticated cleanup
        }
    }
    
    /// Clear all ignore lists
    public func clear() {
        queue.async(flags: .barrier) {
            self.ignoredFiles.removeAll()
            self.predictiveIgnores.removeAll()
            self.ignorePatterns.removeAll()
        }
    }
    
    /// Clear only the standard ignore list
    public func clearIgnored() {
        queue.async(flags: .barrier) {
            self.ignoredFiles.removeAll()
        }
    }
    
    /// Clear only the predictive ignore list
    public func clearPredictive() {
        queue.async(flags: .barrier) {
            self.predictiveIgnores.removeAll()
        }
    }
    
    /// Clear only the pattern list
    public func clearPatterns() {
        queue.async(flags: .barrier) {
            self.ignorePatterns.removeAll()
        }
    }
    
    /// Get the current count of ignored files
    public var ignoredCount: Int {
        queue.sync { ignoredFiles.count }
    }
    
    /// Get the current count of predictively ignored files
    public var predictiveCount: Int {
        queue.sync { predictiveIgnores.count }
    }
    
    /// Get the current count of ignore patterns
    public var patternCount: Int {
        queue.sync { ignorePatterns.count }
    }
    
    // MARK: - Private Methods
    
    private func matchesGlobPattern(fileName: String, pattern: String) -> Bool {
        // Simple glob pattern matching
        // Convert glob pattern to regex
        var regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        
        // Anchor the pattern
        regexPattern = "^" + regexPattern + "$"
        
        return fileName.range(of: regexPattern, options: .regularExpression) != nil
    }
}