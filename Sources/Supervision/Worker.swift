//
//  Worker.swift
//  Supervision
//
//  Created by John on 12/2/25.
//

import OSLog

actor Worker<Action: Sendable, Environment: Sendable>: Sendable {
    var tasks: [String: Task<Action?, Never>]
    private let logger = Logger(subsystem: "Supervision", category: "Worker<\(Action.self), \(Environment.self)>")
    
    init() {
        self.tasks = [:]
    }
    
    isolated deinit {
        cancelAll()
    }
    
    func cancel(taskID: String) {
        tasks[taskID]?.cancel()
        tasks[taskID] = nil
    }
    
    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
    
    // runs the work
    // if a work is running with the same ID, then the work that is running is prioritized and the newest run call is dismissed
    func run(
        _ work: Work<Action, Environment>,
        using environment: Environment
    ) async -> Action? {
        switch work.operation {
        case .none:
            return nil
            
        case .cancellation(let id):
            cancel(taskID: id)
            return nil
            
        case .fireAndForget(let priority, let operation):
            Task(priority: priority) {
                do {
                    try await operation(environment)
                } catch {
                    logger.debug("Fire-and-forget work failed: \(error)")
                }
            }
            return nil

        case .task(let priority, let operationWork):
            let errorHandler = work.onError
            let cancellationID = work.cancellationID

            let task = Task<Action?, Never>(priority: priority) {
                do {
                    let data = try await operationWork(environment)
                    return data
                } catch {
                    guard let onError = errorHandler else {
                        logger.error("""
                        Received Error: \(error.localizedDescription)
                        At: \(Date.now.formatted())
                        
                        Work was not given a callback for error cases.
                        Therefore no action will be emited at this point.
                        Use .onError function to provide a solution for error cases
                        """)
                        return nil
                    }
                    
                    return onError(error)
                }
            }
            
            if let cancellationID = cancellationID {
                guard self.tasks[cancellationID] == nil else {
                    logger.info("""
                    Duplicate cancellationID for Work is received.
                    A work with the same cancellation ID: \(cancellationID) is already running
                    The oldest is prioritized and the newest will be ignored.
                    
                    Please cancel the ongoing task if this priority does not suit your flow 
                    """)
                    return nil
                }
                
                self.tasks[cancellationID] = task
                
                let result = await perform(task: tasks[cancellationID])
                
                defer { self.tasks.removeValue(forKey: cancellationID) }

                return result
            } else {
                return await perform(task: task)
            }
        }
    }
    
    @concurrent
    private func perform(task: Task<Action?, Never>?) async -> Action? {
        return await task?.value
    }
    
    @concurrent
    private func perform(task: Task<Action?, Never>) async -> Action? {
        return await task.value
    }
}
