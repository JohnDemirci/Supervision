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
actor Worker<Action: Sendable, Environment: Sendable, CancellationID: Cancellation>: Sendable {
    /// Active tasks indexed by their cancellation ID.
    var tasks: [CancellationID: Task<Action?, Never>]

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
    func cancel(taskID: CancellationID) {
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
        _ work: Work<Action, Environment, CancellationID>,
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
                    A work with the same cancellation ID is already running
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
            
        case .subscribe:
            // Subscriptions are handled by runSubscription() which emits multiple values
            // This case should not be reached when using the proper API
            logger.warning("Subscribe work should use runSubscription() instead of run()")
            return nil
        }
    }

    /// Executes a subscription work unit, emitting each value through the provided handler.
    ///
    /// Unlike `run()`, which returns a single action, subscriptions emit multiple actions
    /// over time. Each value from the async sequence is passed to the `onAction` handler.
    ///
    /// - Parameters:
    ///   - work: The subscription work unit to execute.
    ///   - environment: The environment/dependencies for the work.
    ///   - onAction: A handler called for each action emitted by the subscription.
    ///
    /// The subscription runs until:
    /// - The async sequence completes naturally
    /// - The task is cancelled via `cancel(taskID:)`
    /// - An error occurs (handled via `.catch` or logged)
    func runSubscription(
        _ work: Work<Action, Environment, CancellationID>,
        using environment: Environment,
        onAction: @MainActor @Sendable @escaping (Action) -> Void
    ) async {
        guard case let .subscribe(sequence) = work.operation else {
            logger.warning("runSubscription called with non-subscribe work. Ignoring.")
            return
        }

        guard let cancellationID = work.cancellationID else {
            logger.warning("Subscribe work requires a cancellationID. Ignoring.")
            return
        }

        guard tasks[cancellationID] == nil else {
            logger.info("""
            Duplicate cancellationID for Subscribe Work received.
            A work with the same cancellation ID is already running.
            The oldest is prioritized and the newest will be ignored.

            Please cancel the ongoing task if this priority does not suit your flow.
            """)
            return
        }

        let errorHandler = work.onError

        let task = Task<Action?, Never> {
            do {
                let stream = try await sequence(environment)

                for try await value in stream {
                    if Task.isCancelled { break }

                    await onAction(value)
                }

                return nil
            } catch is CancellationError {
                return nil
            } catch {
                guard let onError = errorHandler else {
                    self.logger.error("""
                    Subscribe work threw error: \(error.localizedDescription)
                    At: \(Date.now.formatted())

                    Work was not given a callback for error cases.
                    Therefore no action will be emitted at this point.
                    Use .catch { } to convert this error to an action.
                    """)
                    return nil
                }

                return onError(error)
            }
        }

        tasks[cancellationID] = task

        // Await the task completion (handles errors and cleanup)
        let finalAction = await perform(task: task)

        // Clean up the task from tracking
        tasks.removeValue(forKey: cancellationID)

        // If there's a final action (from error handler), emit it
        if let finalAction {
            await onAction(finalAction)
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
