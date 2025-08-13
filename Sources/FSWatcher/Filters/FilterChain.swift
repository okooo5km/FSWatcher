//
//  FilterChain.swift
//  FSWatcher
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import Foundation

/// A chain of filters that can be applied to file system events
public struct FilterChain {
    private var filters: [FileFilter] = []
    
    /// Initialize an empty filter chain
    public init() {}
    
    /// Initialize with an array of filters
    /// - Parameter filters: The initial filters
    public init(filters: [FileFilter]) {
        self.filters = filters
    }
    
    /// Add a filter to the chain
    /// - Parameter filter: The filter to add
    public mutating func add(_ filter: FileFilter) {
        filters.append(filter)
    }
    
    /// Remove all filters from the chain
    public mutating func clear() {
        filters.removeAll()
    }
    
    /// Check if the chain is empty
    public var isEmpty: Bool {
        filters.isEmpty
    }
    
    /// The number of filters in the chain
    public var count: Int {
        filters.count
    }
    
    /// Check if a URL matches all filters in the chain (AND logic)
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL matches all filters
    public func matches(_ url: URL) -> Bool {
        // If no filters, everything matches
        guard !filters.isEmpty else { return true }
        
        // All filters must match (AND logic)
        return filters.allSatisfy { $0.matches(url) }
    }
    
    /// Check if a URL matches any filter in the chain (OR logic)
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL matches any filter
    public func matchesAny(_ url: URL) -> Bool {
        // If no filters, nothing matches in OR mode
        guard !filters.isEmpty else { return false }
        
        // Any filter can match (OR logic)
        return filters.contains { $0.matches(url) }
    }
    
    /// Filter an array of URLs through the chain
    /// - Parameter urls: The URLs to filter
    /// - Returns: URLs that match all filters
    public func filter(_ urls: [URL]) -> [URL] {
        urls.filter { matches($0) }
    }
    
    /// Filter an array of URLs using OR logic
    /// - Parameter urls: The URLs to filter
    /// - Returns: URLs that match any filter
    public func filterAny(_ urls: [URL]) -> [URL] {
        urls.filter { matchesAny($0) }
    }
}