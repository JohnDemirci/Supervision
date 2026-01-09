//
//  Work.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

import Foundation

/// A unit of asynchronous work that produces an `Output` using an `Environment`.
///
/// `Work` is the effect type for the Supervision framework. It encapsulates async operations
/// that can be cancelled, composed, and transformed using functional patterns.
///
/// ## Overview
///
/// Work represents side effects in your application—network requests, database operations,
/// timers, and other async tasks. The Supervisor executes Work and routes the resulting
/// actions back through your feature's `process` method.
///
/// ```swift
/// func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
///     switch action {
///     case .fetchButtonTapped:
///         return .run { env in
///             let data = try await env.apiClient.fetch()
///             return .dataLoaded(data)
///         }
///     case .dataLoaded(let data):
///         context.state.data = data
///         return .empty()
///     }
/// }
/// ```
///
/// ## Error Handling
///
/// By default, errors thrown during work execution are **logged but not propagated**.
/// No action is emitted when an unhandled error occurs. This follows the "log-by-default,
/// opt-in recovery" pattern common in effect systems.
///
/// To handle errors and convert them to actions, use one of these approaches:
///
/// ### Using `catch` for error-only handling:
/// ```swift
/// Work.run { env in
///     try await env.apiClient.fetch()
/// }
/// .catch { error in
///     .fetchFailed(error.localizedDescription)
/// }
/// ```
///
/// ### Using `run(_:toAction:)` for Result-based handling (recommended):
/// ```swift
/// Work.run { env in
///     try await env.apiClient.fetch()
/// } toAction: { result in
///     .fetchCompleted(result)
/// }
/// ```
///
/// ## Cancellation
///
/// Work can be tagged with a cancellation ID and cancelled later:
///
/// ```swift
/// // Start cancellable work
/// return .run { env in
///     try await env.longRunningTask()
/// }
/// .cancellable(id: "my-task")
///
/// // Cancel it later
/// return .cancel("my-task")
/// ```
///
/// ## Composition
///
/// Work supports functional composition via `map` and `flatMap`:
///
/// ```swift
/// Work.run { env in
///     try await env.fetchRawData()
/// }
/// .map { rawData in
///     .processedData(transform(rawData))
/// }
/// ```
///
/// - Note: `map` and `flatMap` only work on `.task` operations. Attempting to transform
///   `.none`, `.cancellation`, or `.fireAndForget` operations will throw a `Failure`.
public struct Work<Output, Environment, CancellationID: Cancellation>: Sendable {
    enum Operation {
        case none
        case cancellation(CancellationID)
        case fireAndForget(
            TaskPriority?,
            @Sendable (Environment) async throws -> Void
        )
        case task(
            TaskPriority?,
            @Sendable (Environment) async throws -> Output
        )
        case subscribe(
            @Sendable (Environment) async throws -> AsyncThrowingStream<Output, Error>
        )
    }

    let cancellationID: CancellationID?
    let operation: Operation
    let onError: (@Sendable (Error) -> Output)?

    init(
        cancellationID: CancellationID? = nil,
        operation: Operation,
        onError: (@Sendable (Error) -> Output)? = nil
    ) {
        self.operation = operation
        self.onError = onError
        self.cancellationID = cancellationID
    }
}

// MARK: - Factory Methods

public extension Work {
    /// Creates an empty work unit that performs no operation.
    ///
    /// Use this when an action requires no side effects:
    ///
    /// ```swift
    /// case .incrementButtonTapped:
    ///     context.state.count += 1
    ///     return .empty()
    /// ```
    ///
    /// - Returns: A work unit with no operation.
    static func empty<O, E>() -> Work<O, E, Never> {
        Work<O, E, Never>(operation: .none)
    }

    /// Creates a work unit that cancels a previously started task.
    ///
    /// Use this to cancel long-running or in-flight work:
    ///
    /// ```swift
    /// case .cancelButtonTapped:
    ///     return .cancel("search-request")
    /// ```
    ///
    /// - Parameter id: The cancellation ID of the work to cancel.
    ///   Must match the ID passed to ``cancellable(id:)``.
    /// - Returns: A work unit that cancels the specified task.
    static func cancel(_ id: CancellationID) -> Work<Output, Environment, CancellationID> {
        Work(
            cancellationID: id,
            operation: .cancellation(id),
            onError: nil
        )
    }

    /// Creates a work unit that executes without producing an action.
    ///
    /// Use this for side effects where you don't need a response:
    ///
    /// ```swift
    /// case .logEvent(let event):
    ///     return .fireAndForget { env in
    ///         await env.analytics.log(event)
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Defaults to `nil` (inherits from context).
    ///   - body: The async operation to execute. Errors are logged but not propagated.
    /// - Returns: A work unit that executes the operation without emitting an action.
    static func fireAndForget(
        priority: TaskPriority? = nil,
        _ body: @Sendable @escaping (Environment) async throws -> Void
    ) -> Work<Output, Environment, Never> {
        Work<Output, Environment, Never>(
            operation: .fireAndForget(priority, body)
        )
    }

    /// Creates a work unit that executes an operation and transforms the result.
    ///
    /// This is the **recommended** approach for handling both success and failure cases.
    /// The `toAction` closure receives a `Result` that you can pattern match or pass directly:
    ///
    /// ```swift
    /// case .fetchButtonTapped:
    ///     return .run { env in
    ///         try await env.apiClient.fetchUsers()
    ///     } toAction: { result in
    ///         .usersResponse(result)
    ///     }
    ///
    /// case .usersResponse(.success(let users)):
    ///     context.state.users = users
    ///     return .empty()
    ///
    /// case .usersResponse(.failure(let error)):
    ///     context.state.error = error.localizedDescription
    ///     return .empty()
    /// ```
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Defaults to `nil` (inherits from context).
    ///   - body: The async operation that produces a value or throws an error.
    ///   - toAction: A closure that transforms the `Result` into an action.
    /// - Returns: A work unit that executes the operation and emits the transformed action.
    static func run<Value>(
        priority: TaskPriority? = nil,
        _ body: @Sendable @escaping (Environment) async throws -> Value,
        toAction: @Sendable @escaping (Result<Value, Error>) -> Output
    ) -> Work<Output, Environment, CancellationID> {
        Work<Output, Environment, CancellationID>(
            operation: .task(priority) { env in
                do {
                    let value = try await body(env)
                    return toAction(.success(value))
                } catch {
                    return toAction(.failure(error))
                }
            }
        )
    }

    /// Creates a work unit that executes an operation and returns the result directly.
    ///
    /// Use this when the operation directly produces an action:
    ///
    /// ```swift
    /// case .fetchButtonTapped:
    ///     return .run { env in
    ///         let users = try await env.apiClient.fetchUsers()
    ///         return .usersLoaded(users)
    ///     }
    /// ```
    ///
    /// - Important: If the operation throws an error, it is **logged but not propagated**.
    ///   No action will be emitted. Use ``catch(_:)`` or ``run(priority:_:toAction:)``
    ///   to handle errors explicitly.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Defaults to `nil` (inherits from context).
    ///   - body: The async operation that produces an action or throws an error.
    /// - Returns: A work unit that executes the operation and emits the resulting action.
    static func run(
        priority: TaskPriority? = nil,
        _ body: @Sendable @escaping (Environment) async throws -> Output
    ) -> Work<Output, Environment, CancellationID> {
        Work<Output, Environment, CancellationID>(operation: .task(priority, body))
    }

    /// Creates work that subscribes to an async sequence and emits actions over time.
    ///
    /// Use this to create long-running subscriptions to streams of data like:
    /// - WebSocket connections
    /// - Database change notifications
    /// - Timer events
    /// - Sensor data streams
    ///
    /// ## Example: Timer Subscription
    ///
    /// ```swift
    /// case .startTimer:
    ///     return .subscribe(cancellationID: "timer") { env in
    ///         AsyncStream { continuation in
    ///             Task {
    ///                 while !Task.isCancelled {
    ///                     try await Task.sleep(for: .seconds(1))
    ///                     continuation.yield(.tick)
    ///                 }
    ///                 continuation.finish()
    ///             }
    ///         }
    ///     }
    /// ```
    ///
    /// ## Example: NotificationCenter as AsyncSequence
    ///
    /// ```swift
    /// case .observeKeyboardChanges:
    ///     return .subscribe(cancellationID: "keyboard") { env in
    ///         NotificationCenter.default
    ///             .notifications(named: UIResponder.keyboardWillShowNotification)
    ///             .map { notification in
    ///                 .keyboardWillShow(notification)
    ///             }
    ///     }
    /// ```
    ///
    /// - Important: Subscribe work **requires** a `cancellationID`. Without one,
    ///   the subscription will be ignored and a warning logged.
    ///
    /// - Note: The subscription runs until:
    ///   - The sequence finishes naturally
    ///   - The task is cancelled via `.cancel(cancellationID)`
    ///   - The worker/supervisor is deallocated
    ///
    /// - Parameters:
    ///   - cancellationID: Required identifier for cancelling the subscription
    ///   - body: A closure that creates an async sequence from the environment
    /// - Returns: A work unit that subscribes to the async sequence
    static func subscribe(
        cancellationID: CancellationID,
        _ body: @Sendable @escaping (Environment) async throws -> AsyncThrowingStream<Output, Error>
    ) -> Work<Output, Environment, CancellationID> {
        Work<Output, Environment, CancellationID>.init(
            cancellationID: cancellationID,
            operation: .subscribe({ env in
                try await body(env)
            }),
            onError: nil
        )
    }
    
    static func subscribe<Value>(
        cancellationID: CancellationID? = nil,
        _ body: @Sendable @escaping (Environment) async throws -> AsyncThrowingStream<Value, Error>,
        toAction: @Sendable @escaping (Result<Value, Error>) -> Output
    ) -> Work<Output, Environment, CancellationID> where Output: Sendable, Value: Sendable {
        Work<Output, Environment, CancellationID>(
            cancellationID: cancellationID,
            operation: .subscribe({ env in
                let currentStream = try await body(env)
                return AsyncThrowingStream { continuation in
                    Task {
                        do {
                            for try await value in currentStream {
                                continuation.yield(toAction(.success(value)))
                            }
                            continuation.finish()
                        } catch {
                            continuation.yield(toAction(.failure(error)))
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }),
            onError: nil
        )
    }
}

// MARK: - Transformations

public extension Work {
    /// Transforms the output of this work unit.
    ///
    /// Use `map` to transform the successful output into a different type:
    ///
    /// ```swift
    /// Work.run { env in
    ///     try await env.apiClient.fetchUserData()
    /// }
    /// .map { userData in
    ///     .userProfileLoaded(UserProfile(from: userData))
    /// }
    /// ```
    ///
    /// - Parameter transform: A closure that transforms the output into a new type.
    /// - Returns: A new work unit that produces the transformed output.
    /// - Throws: ``Failure`` if called on `.none`, `.cancellation`, or `.fireAndForget` operations.
    func map<NewOutput>(
        _ transform: @Sendable @escaping (Output) -> NewOutput
    ) -> Work<NewOutput, Environment, CancellationID> where Output: Sendable, NewOutput: Sendable {
        switch operation {
        case .none:
            preconditionFailure("Attempting to map a non-task work unit")

        case .cancellation:
            preconditionFailure("Attempting to map a cancellation work unit")

        case .fireAndForget:
            preconditionFailure("Attempting to map a fire-and-forget work unit")

        case let .task(priority, work):
            return Work<NewOutput, Environment, CancellationID>(
                cancellationID: cancellationID,
                operation: .task(priority) { env in
                    let output = try await work(env)
                    return transform(output)
                },
                onError: nil
            )
            
        case let .subscribe(sequence):
            return Work<NewOutput, Environment, CancellationID>(
                cancellationID: self.cancellationID,
                operation: .subscribe({ env in
                    let originalStream = try await sequence(env)
                    return AsyncThrowingStream<NewOutput, Error> { continuation in
                        Task {
                            do {
                                for try await element in originalStream {
                                    continuation.yield(transform(element))
                                }
                                continuation.finish()
                            } catch {
                                continuation.finish(throwing: error)
                            }
                        }
                    }
                }),
                onError: nil
            )
        }
    }

    /// Provides error handling for this work unit.
    ///
    /// When work throws an error and no `catch` handler is provided, the error is logged
    /// and no action is emitted. Use this method to transform errors into actions:
    ///
    /// ```swift
    /// Work.run { env in
    ///     try await env.apiClient.fetchUsers()
    /// }
    /// .catch { error in
    ///     .fetchFailed(error.localizedDescription)
    /// }
    /// ```
    ///
    /// For handling both success and failure, consider using ``run(priority:_:toAction:)`` instead.
    ///
    /// - Parameter transform: A closure that converts an error into an output action.
    /// - Returns: A new work unit with the error handler attached.
    /// - Note: The `catch` handler is only invoked for `.task` operations.
    ///   For `.fireAndForget`, errors are always logged silently.
    func `catch`(
        _ transform: @Sendable @escaping (Error) -> Output
    ) -> Work<Output, Environment, CancellationID> {
        Work<Output, Environment, CancellationID>(
            cancellationID: cancellationID,
            operation: operation,
            onError: { error in
                transform(error)
            }
        )
    }

    /// Chains this work unit with another that depends on its output.
    ///
    /// Use `flatMap` when one async operation depends on the result of another:
    ///
    /// ```swift
    /// Work.run { env in
    ///     try await env.authClient.login()
    /// }
    /// .flatMap { token in
    ///     Work.run { env in
    ///         try await env.apiClient.fetchProfile(token: token)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter transform: A closure that takes the output and returns a new work unit.
    /// - Returns: A new work unit that chains both operations.
    /// - Throws: ``Failure`` if called on `.none`, `.cancellation`, or `.fireAndForget` operations.
    /// - Precondition: The returned work must be a `.task` operation.
    func flatMap<NewOutput>(
        _ transform: @Sendable @escaping (Output) -> Work<NewOutput, Environment, CancellationID>
    ) -> Work<NewOutput, Environment, CancellationID> {
        switch operation {
        case .none:
            preconditionFailure("Attempting to flatMap a none work unit")

        case .cancellation:
            preconditionFailure("Attempting to flatMap a cancellation work unit")

        case .fireAndForget:
            preconditionFailure("Attempting to flatMap a fireAndForget work unit")

        case .subscribe:
            preconditionFailure("Attempting to flat map a subscribe work unit")

        case let .task(priority, work):
            return Work<NewOutput, Environment, CancellationID>(
                operation: .task(priority) { env in
                    let newWork = try await transform(work(env))

                    switch newWork.operation {
                    case .none, .cancellation, .fireAndForget, .subscribe:
                        preconditionFailure("Cannot flatMap into a non-task work unit")
                    case let .task(_, action):
                        return try await action(env)
                    }
                }
            )
        }
    }

    /// Adds a cancellation ID to this work unit.
    ///
    /// Tag work with an ID so it can be cancelled later using ``cancel(_:)``:
    ///
    /// ```swift
    /// // Start a cancellable search request
    /// case .searchQueryChanged(let query):
    ///     return .run { env in
    ///         try await env.searchClient.search(query)
    ///     }
    ///     .cancellable(id: "search")
    ///
    /// // Cancel it when the user clears the search
    /// case .searchCleared:
    ///     return .cancel("search")
    /// ```
    ///
    /// - Parameter id: A unique identifier for this work unit.
    /// - Returns: A new work unit with the cancellation ID attached.
    /// - Note: If work with the same ID is already running, the new work will be dropped
    ///   and a warning will be logged. Cancel existing work first if you want to replace it.
    func cancellable(id: CancellationID) -> Work<Output, Environment, CancellationID> {
        Work(cancellationID: id, operation: operation, onError: onError)
    }
}

extension Never: Cancellation {}
