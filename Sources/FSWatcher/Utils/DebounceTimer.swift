//
//  DebounceTimer.swift
//  FSWatcher
//
//  Created by FSWatcher on 2025/08/13.
//

import Foundation

/// A timer that debounces rapid events
internal class DebounceTimer {
    private var workItem: DispatchWorkItem?
    private let interval: TimeInterval
    private let queue: DispatchQueue
    
    /// Initialize a new debounce timer
    /// - Parameters:
    ///   - interval: The debounce interval in seconds
    ///   - queue: The queue to execute the action on
    init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }
    
    /// Debounce an action
    /// - Parameter action: The action to execute after the debounce interval
    func debounce(_ action: @escaping () -> Void) {
        // Cancel the previous work item if it exists
        workItem?.cancel()
        
        // Create a new work item
        let newWorkItem = DispatchWorkItem {
            action()
        }
        
        // Store the new work item
        workItem = newWorkItem
        
        // Schedule the new work item
        queue.asyncAfter(deadline: .now() + interval, execute: newWorkItem)
    }
    
    /// Cancel any pending debounced action
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
    
    deinit {
        cancel()
    }
}