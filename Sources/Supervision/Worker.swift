//
//  Worker.swift
//  Supervision
//
//  Created by John on 12/2/25.
//

import OSLog

/// An actor responsible for executing asynchronous work and managing task lifecycles.
///
/// `Worker` is the execution engine for ``Work`` units. It handles task creation,
/// cancellation, and error handling, ensuring thread-safe async operations.
///
/// ## Overview
///
/// Worker is used internally by ``Supervisor`` to execute side effects returned
/// from ``FeatureProtocol/process(action:context:)``. You typically don't interact
/// with Worker directly.
///
/// ## Task Management
///
/// Worker tracks cancellable tasks by their cancellation ID:
///
/// - **Unique IDs**: Each cancellable work must have a unique ID
/// - **Duplicate handling**: If work with the same ID is already running,
///   new work is dropped and a warning is logged
/// - **Automatic cleanup**: Tasks are removed from tracking after completion
///
/// ## Cancellation
///
/// Tasks can be cancelled individually or all at once:
///
/// - ``cancel(taskID:)``: Cancels a specific task by ID
/// - ``cancelAll()``: Cancels all tracked tasks (called on deinit)
///
/// ## Error Handling
///
/// When work throws an error:
/// 1. If an `onError` handler was provided (via `.catch`), it's called to produce an action
/// 2. Otherwise, the error is logged and no action is emitted
///
/// This follows the "log-by-default, opt-in recovery" pattern.
///
/// ## Thread Safety
///
/// Worker is an `actor`, ensuring all task management is thread-safe.
/// The `@concurrent` annotation on `perform` methods allows concurrent
/// task awaiting without blocking the actor.
actor Worker<Action: Sendable, Environment: Sendable>: Sendable {
    /// Active tasks indexed by their cancellation ID.
    var tasks: [String: Task<Action?, Never>]

    private let logger = Logger(subsystem: "Supervision", category: "Worker<\(Action.self), \(Environment.self)>")

    init() {
        tasks = [:]
    }

    /// Cancels all tracked tasks when the worker is deallocated.
    isolated deinit {
        cancelAll()
    }

    /// Cancels a specific task by its cancellation ID.
    ///
    /// - Parameter taskID: The cancellation ID of the task to cancel.
    ///
    /// If no task exists with the given ID, this method does nothing.
    func cancel(taskID: String) {
        tasks[taskID]?.cancel()
        tasks[taskID] = nil
    }

    /// Cancels all tracked tasks.
    ///
    /// Called automatically when the worker is deallocated.
    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Executes a work unit and returns the resulting action.
    ///
    /// - Parameters:
    ///   - work: The work unit to execute.
    ///   - environment: The environment/dependencies for the work.
    /// - Returns: The action produced by the work, or `nil` if no action should be sent.
    ///
    /// ## Behavior by Work Type
    ///
    /// - `.none`: Returns `nil` immediately
    /// - `.cancellation(id)`: Cancels the task with that ID, returns `nil`
    /// - `.fireAndForget`: Spawns a detached task, returns `nil` immediately
    /// - `.task`: Executes and returns the resulting action
    ///
    /// ## Duplicate Cancellation IDs
    ///
    /// If work has a cancellation ID that's already in use, the new work is
    /// dropped and a warning is logged. The existing task continues running.
    func run(
        _ work: Work<Action, Environment>,
        using environment: Environment
    ) async -> Action? {
        switch work.operation {
        case .none:
            return nil

        case let .cancellation(id):
            cancel(taskID: id)
            return nil

        case let .fireAndForget(priority, operation):
            Task(priority: priority) {
                do {
                    try await operation(environment)
                } catch {
                    logger.debug("Fire-and-forget work failed: \(error)")
                }
            }
            return nil

        case let .task(priority, operationWork):
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
                        Therefore no action will be emitted at this point.
                        Use .catch { } to convert this error to an action
                        """)
                        return nil
                    }

                    return onError(error)
                }
            }

            if let cancellationID = cancellationID {
                guard tasks[cancellationID] == nil else {
                    logger.info("""
                    Duplicate cancellationID for Work is received.
                    A work with the same cancellation ID: \(cancellationID) is already running
                    The oldest is prioritized and the newest will be ignored.

                    Please cancel the ongoing task if this priority does not suit your flow 
                    """)
                    return nil
                }

                tasks[cancellationID] = task

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
