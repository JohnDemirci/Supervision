//
//  Worker.swift
//  Supervision
//
//  Created by John on 12/2/25.
//

import Foundation
import OSLog

actor Worker<Action: Sendable, Environment: Sendable>: Sendable {
    private struct TrackedTask: Sendable {
        let token: UUID
        let task: Task<Void, Never>
    }

    /// Active tasks indexed by their cancellation ID.
    private var tasks: [AnyHashableSendable: TrackedTask]
    private var untracked: [UUID: Task<Void, Never>] = [:]

    private var lastExecutionTimes: [AnyHashableSendable: ContinuousClock.Instant] = [:]
    private let logger = Logger(
        subsystem: "Supervision",
        category: "Worker<\(Action.self), \(Environment.self)>"
    )

    init() {
        tasks = [:]
    }

    /// Cancels all tracked tasks when the worker is deallocated.
    isolated deinit {
        cancelAll()
    }

    /*
     this function takes a work and makes the proper execution choices
     
     the boolen return value indicates that if there are currently running additional works, should we continue running them. if the value is false then we discard the tasks.
     
     this is particularly beneficial for the concatenated works
     */
    @discardableResult
    func handle(
        work: Work<Action, Environment>,
        environment: Environment,
        send: @escaping @Sendable (Action) async -> Void
    ) async -> Bool {
        switch work.operation {
        case .done:
            return true
        case .cancel(let id):
            cancel(taskID: id)
            return true
        case .run(let run):
            return await processRun(run: run, environment: environment, send: send)
        case .concatenate(let works):
            return await processConcatenate(works, environment: environment, send: send)
        case .merge(let works):
            await processMerge(works: works, environment: environment, send: send)
            return true
        }
    }
}

// MARK: - Perform Work

extension Worker {
    private enum Registration {
        case tracked(id: AnyHashableSendable, token: UUID)
        case untracked(token: UUID)
    }

    private func processRun(
        run: Work<Action, Environment>.Run,
        environment: Environment,
        send: @escaping @Sendable (Action) async -> Void,
    ) async -> Bool {
        guard handleCancelInFlight(run: run) else { return false }
        guard handleThrottle(run: run) else { return true }

        let task = makeTask(run: run, environment: environment, send: send)
        let registration = register(task: task, cancellationID: run.configuration.cancellationID)

        if !run.configuration.fireAndForget {
            defer { cleanup(registration) }
            await task.value
            return !task.isCancelled
        }

        scheduleCleanup(registration, task: task)
        return true
    }

    private func makeTask(
        run: Work<Action, Environment>.Run,
        environment: Environment,
        send: @escaping @Sendable (Action) async -> Void
    ) -> Task<Void, Never> {
        Task<Void, Never>(
            name: run.configuration.name,
            priority: run.configuration.priority,
            operation: {
                if let debounce = run.configuration.debounce {
                    try? await Task.sleep(for: debounce)
                    guard !Task.isCancelled else { return }
                }

                await run.execute.execution(environment, send)
            }
        )
    }

    private func register(
        task: Task<Void, Never>,
        cancellationID: AnyHashableSendable?
    ) -> Registration {
        let token = UUID()
        if let id = cancellationID {
            tasks[id] = TrackedTask(token: token, task: task)
            return .tracked(id: id, token: token)
        }
        untracked[token] = task
        return .untracked(token: token)
    }

    private func cleanup(_ registration: Registration) {
        switch registration {
        case let .tracked(id, token):
            clearTask(id: id, token: token)
        case let .untracked(token):
            clearUntrackedTask(token)
        }
    }

    private func scheduleCleanup(
        _ registration: Registration,
        task: Task<Void, Never>
    ) {
        Task { [weak self] in
            _ = await task.result
            await self?.cleanup(registration)
        }
    }

    private func processMerge(
        works: [Work<Action, Environment>],
        environment: Environment,
        send: @escaping @Sendable (Action) async -> Void
    ) async {
        guard !works.isEmpty else {
            // TODO: show runtime warning
            return
        }

        if works.count == 1 {
            await handle(work: works.first!, environment: environment, send: send)
            return
        }

        await withTaskGroup { group in
            for work in works {
                group.addTask { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    await self.handle(work: work, environment: environment, send: send)
                }
            }

            await group.waitForAll()
        }
    }

    private func processConcatenate(
        _ works: [Work<Action, Environment>],
        environment: Environment,
        send: @escaping @Sendable (Action) async -> Void
    ) async -> Bool {
        for work in works {
            let shouldContinue = await handle(work: work, environment: environment, send: send)

            if !shouldContinue {
                return false
            }
        }

        return true
    }
}

// MARK: - Task Cleanup

extension Worker {
    /// Cancels a specific task by its cancellation ID.
    ///
    /// - Parameter taskID: The cancellation ID of the task to cancel.
    ///
    /// If no task exists with the given ID, this method does nothing.
    @inline(__always)
    private func cancel(taskID: AnyHashableSendable) {
        tasks[taskID]?.task.cancel()
        tasks[taskID] = nil
    }

    /// Cancels all tracked tasks.
    ///
    /// Called automatically when the worker is deallocated.
    @inline(__always)
    private func cancelAll() {
        tasks.values.forEach { $0.task.cancel() }
        untracked.values.forEach { $0.cancel() }

        tasks.removeAll()
        untracked.removeAll()
    }

    @inline(__always)
    private func clearTask(id: AnyHashableSendable, token: UUID) {
        guard tasks[id]?.token == token else { return }
        tasks[id] = nil
    }

    @inline(__always)
    private func clearUntrackedTask(_ id: UUID) {
        untracked[id]?.cancel()
        untracked[id] = nil
    }
}

// MARK: - Process Helper

extension Worker {
    @inline(__always)
    func handleCancelInFlight(
        run: Work<Action, Environment>.Run
    ) -> Bool {
        guard let cancellationID = run.configuration.cancellationID else {
            logger.debug("No cancellation ID, skipping cancel-in-flight check")
            return true
        }

        if run.configuration.cancelInFlight {
            cancel(taskID: cancellationID)
        } else if tasks[cancellationID] != nil {
            return false
        }

        return true
    }

    @inline(__always)
    func handleThrottle(
        run: Work<Action, Environment>.Run
    ) -> Bool {
        if let throttle = run.configuration.throttle {
            if let id = run.configuration.cancellationID {
                let now = ContinuousClock.now
                if let lastTime = lastExecutionTimes[id] {
                    let elapsed = now - lastTime
                    if elapsed < throttle {
                        logger.debug("Throttled effect \(id)")
                        return false
                    }
                }
                lastExecutionTimes[id] = now
            }
        } else if let id = run.configuration.cancellationID {
            // if you do not provide a throtle for a given id, the throttle is reset.
            // we might implement a TTL for this instead in the future.
            lastExecutionTimes[id] = nil
        }

        return true
    }
}
