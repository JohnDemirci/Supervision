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
    private var tasks: [CancellationID: Task<Action?, Never>]

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
    @inline(__always)
    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    @inline(__always)
    func processCancel(
        _ work: Cancel<Action, Environment, CancellationID>
    ) {
        cancel(taskID: work.id)
    }

    func processFireAndForget(
        _ work: FireAndForget<Action, Environment, CancellationID>,
        using dependency: Environment
    ) {
        Task {
            await work.execute(with: dependency)
        }
    }

    func processRun(
        _ work: any RunnableWork<Action, Environment, CancellationID>,
        using dependency: Environment
    ) async -> Action? {
        let task = Task<Action?, Never>(
            name: work.name,
            priority: work.priority
        ) {
            guard !Task.isCancelled else {
                logger.info("""
                Task: \(Task.name ?? "") was cancellated
                """)
                return nil
            }

            return await work.execute(with: dependency)
        }

        if let cancellationID = work.cancellationID {
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
            let value = await task.value
            tasks[cancellationID] = nil
            return value
        } else {
            return await task.value
        }
    }

    func processSubscription<T: SubscriptionWork<Action, Environment, CancellationID>>(
        work: T,
        using dependency: Environment,
        onAction: @MainActor @Sendable @escaping (Action) -> Void
    ) {
        guard tasks[work.cancellationID] == nil else {
            logger.info("Duplicate subscription ID - ignoring")
            return
        }

        let cancellationID = work.cancellationID

        let task = Task<Action?, Never> { [weak self] in
            defer {
                Task { [weak self] in
                    await self?.cancel(taskID: cancellationID)
                }
            }

            do {
                let stream = try await work.subscribe(with: dependency)
                for try await value in stream {
                    guard !Task.isCancelled else { return nil }
                    await onAction(value)
                }
                return nil
            } catch is CancellationError {
                return nil
            } catch {
                await onAction(work.receive(error: error))
                return nil
            }
        }

        tasks[work.cancellationID] = task
    }
}
