//
//  Supervisor.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import OSLog

/// The central coordinator for a feature's state, actions, and side effects.
///
/// `Supervisor` is the runtime that drives your feature. It holds the current state,
/// dispatches actions through your feature's `process` method, and executes async work.
///
/// ## Overview
///
/// A Supervisor manages the lifecycle of a single feature:
///
/// ```swift
/// struct CounterFeature: FeatureProtocol {
///     struct State {
///         var count = 0
///     }
///
///     enum Action {
///         case increment
///         case decrement
///     }
///
///     func process(action: Action, context: borrowing Context<State>) -> Work<Action, Void> {
///         switch action {
///         case .increment:
///             context.state.count += 1
///         case .decrement:
///             context.state.count -= 1
///         }
///         return .empty()
///     }
/// }
///
/// // Create and use a Supervisor
/// let supervisor = Supervisor<CounterFeature>(state: .init(), dependency: ())
/// supervisor.send(.increment)
/// print(supervisor.count)  // 1 (via @dynamicMemberLookup)
/// ```
///
/// ## SwiftUI Integration
///
/// Use `@State` to hold a Supervisor in SwiftUI views:
///
/// ```swift
/// struct CounterView: View {
///     @State private var supervisor = Supervisor<CounterFeature>(
///         state: .init(),
///         dependency: ()
///     )
///
///     var body: some View {
///         VStack {
///             Text("Count: \(supervisor.count)")
///
///             Button("Increment") {
///                 supervisor.send(.increment)
///             }
///         }
///     }
/// }
/// ```
///
/// ## State Access
///
/// Access state properties directly via `@dynamicMemberLookup`:
///
/// ```swift
/// supervisor.count      // Same as supervisor.state.count
/// supervisor.userName   // Same as supervisor.state.userName
/// supervisor.items      // Same as supervisor.state.items
/// ```
///
/// ## Bindings
///
/// Create SwiftUI bindings for two-way data flow:
///
/// ```swift
/// // Action-based binding (recommended)
/// TextField("Name", text: supervisor.binding(\.name, send: { .nameChanged($0) }))
///
/// // Direct binding (for UI-only state)
/// Slider(value: supervisor.directBinding(\.volume))
/// ```
///
/// ## Dependencies
///
/// Inject dependencies for side effects:
///
/// ```swift
/// struct AppDependency {
///     var apiClient: APIClient
///     var database: Database
/// }
///
/// let supervisor = Supervisor<MyFeature>(
///     state: .init(),
///     dependency: AppDependency(apiClient: .live, database: .live)
/// )
/// ```
///
/// ## Identity and Caching
///
/// Supervisors have an ``id`` property used by ``Board`` for caching:
///
/// - For `Identifiable` state, the ID is derived from `state.id`
/// - Otherwise, a type-based ID is generated
/// - Use ``Board`` to manage supervisor lifecycles across views
///
/// ## Thread Safety
///
/// Supervisor is `@MainActor` isolated. All state access and action dispatch
/// must occur on the main thread. Async work in ``Work`` is executed on
/// appropriate executors and results are dispatched back to main.
///
/// ## Lifecycle
///
/// - **Initialization**: Creates the feature instance and starts the action processing loop
/// - **Processing**: Actions flow through `feature.process()` synchronously
/// - **Async Work**: Work is queued and executed by the internal ``Worker``
/// - **Deinitialization**: Cancels all pending work and stops processing
@MainActor
@Observable
@dynamicMemberLookup
public final class Supervisor<Feature: FeatureProtocol> {
    /// The action type defined by the feature.
    public typealias Action = Feature.Action

    /// The dependency type required by the feature for side effects.
    public typealias Dependency = Feature.Dependency

    /// The state type managed by this supervisor.
    public typealias State = Feature.State

    private nonisolated let logger: Logger

    private let actionContinuation: AsyncStream<Work<Action, Dependency>>.Continuation
    private let actionStream: AsyncStream<Work<Action, Dependency>>
    private let dependency: Dependency
    private let worker: Worker<Action, Dependency>

    private var processingTask: Task<Void, Never>?

    /// A unique identifier for this supervisor instance.
    ///
    /// The ID is used by ``Board`` to cache and retrieve supervisors:
    ///
    /// - For `Identifiable` state: derived from `state.id`
    /// - For non-identifiable state: based on `ObjectIdentifier(Supervisor<Feature>.self)`
    ///
    /// This enables efficient supervisor reuse across view updates.
    public let id: ReferenceIdentifier

    /// The feature instance that processes actions.
    let feature: Feature

    /// The current state of the feature.
    ///
    /// State is `@Observable`, so SwiftUI views automatically update when it changes.
    /// Prefer accessing properties via dynamic member lookup:
    ///
    /// ```swift
    /// supervisor.count  // Instead of supervisor.state.count
    /// ```
    ///
    /// - Important: State should be a value type (struct or enum). Using reference
    ///   types will trigger a runtime warning.
    public internal(set) var state: State

    // MARK: - Initialization

    init(
        id: ReferenceIdentifier,
        state: State,
        dependency: Dependency
    ) {
        self.id = id
        self.logger = .init(
            subsystem: "com.Supervision.\(Feature.self)",
            category: "Supervisor"
        )

        let mirror = Mirror(reflecting: state)
        if mirror.displayStyle != .struct, mirror.displayStyle != .enum {
            logger.error(
                """
                ⚠️ Warning: State should be a struct or enum (value type).
                Using reference types (classes) can lead to unexpected behavior.
                Current State type: \(type(of: state))
                """
            )
        }

        self.state = state
        self.dependency = dependency
        self.worker = .init()
        self.feature = Feature()

        let (stream, continuation) = AsyncStream.makeStream(of: Work<Action, Dependency>.self, bufferingPolicy: .unbounded)
        self.actionStream = stream
        self.actionContinuation = continuation

        self.processingTask = Task { [weak self] in
            for await work in stream {
                guard let self else { return }
                await self.processAsyncWork(work)
            }
        }
    }

    isolated deinit {
        actionContinuation.finish()
        processingTask?.cancel()
        processingTask = nil
    }

    /// Provides direct access to state properties via dynamic member lookup.
    ///
    /// This subscript allows you to access state properties directly on the supervisor:
    ///
    /// ```swift
    /// // Instead of:
    /// let name = supervisor.state.userName
    /// let count = supervisor.state.items.count
    ///
    /// // You can write:
    /// let name = supervisor.userName
    /// let count = supervisor.items.count
    /// ```
    ///
    /// - Parameter keyPath: A key path to a property on the state.
    /// - Returns: The value at the specified key path.
    public subscript<Subject>(dynamicMember keyPath: KeyPath<State, Subject>) -> Subject {
        state[keyPath: keyPath]
    }

    /// Dispatches an action to the feature for processing.
    ///
    /// This is the primary way to trigger state changes and side effects. The action
    /// flows through your feature's `process(action:context:)` method synchronously,
    /// and any returned ``Work`` is scheduled for async execution.
    ///
    /// ```swift
    /// // Simple action dispatch
    /// supervisor.send(.increment)
    ///
    /// // Action with associated value
    /// supervisor.send(.userNameChanged("John"))
    ///
    /// // From SwiftUI
    /// Button("Save") {
    ///     supervisor.send(.saveButtonTapped)
    /// }
    /// ```
    ///
    /// ## Processing Flow
    ///
    /// 1. Action is passed to `feature.process(action:context:)`
    /// 2. Feature mutates state via `context.state`
    /// 3. Feature returns ``Work`` describing side effects
    /// 4. Work is executed:
    ///    - `.empty()`: No action taken
    ///    - `.cancel(id)`: Cancels running work with that ID
    ///    - `.run { }`: Queued for async execution
    ///    - `.fireAndForget { }`: Executed without awaiting result
    ///
    /// ## State Updates
    ///
    /// State mutations in `process()` are applied **synchronously** before `send()` returns.
    /// This ensures UI updates immediately reflect the new state:
    ///
    /// ```swift
    /// supervisor.send(.increment)
    /// // supervisor.count is already updated here
    /// ```
    ///
    /// ## Async Work
    ///
    /// Work returned from `process()` is executed asynchronously. When work completes
    /// with an action, that action is automatically dispatched via `send()`:
    ///
    /// ```swift
    /// case .fetchUsers:
    ///     return .run { env in
    ///         let users = try await env.api.fetchUsers()
    ///         return .usersLoaded(users)  // This action is sent automatically
    ///     }
    /// ```
    ///
    /// - Parameter action: The action to dispatch.
    public func send(_ action: Action) {
        let work = withUnsafeMutablePointer(to: &state) { pointer in
            // Pointer valid within the scope
            // Context is ~Copyable and never escapes
            // Everything in here is synchronous.
            let context = Context<Feature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafeMutablePointer(pointer)
            )
            // context is passed as a borrowing
            return feature.process(action: action, context: context)

            // work is returned it has no reference to context or the pointer
        }

        switch work.operation {
        case .none:
            return
        case let .cancellation(id):
            Task { await self.worker.cancel(taskID: id) }
        case .task, .fireAndForget, .subscribe:
            actionContinuation.yield(work)
        }
    }
}

// MARK: - Convenience Initializers

public extension Supervisor where State: Identifiable {
    /// Creates a supervisor with an identifiable state.
    ///
    /// The supervisor's ``id`` is derived from `state.id`, enabling ``Board``
    /// to cache supervisors based on their state identity:
    ///
    /// ```swift
    /// struct UserFeature: FeatureProtocol {
    ///     struct State: Identifiable {
    ///         let id: UUID
    ///         var name: String
    ///     }
    ///     // ...
    /// }
    ///
    /// // Each user gets a unique supervisor
    /// let userSupervisor = Supervisor<UserFeature>(
    ///     state: State(id: user.id, name: user.name),
    ///     dependency: dependencies
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - state: The initial state. Must conform to `Identifiable`.
    ///   - dependency: Dependencies for executing side effects.
    convenience init(
        state: State,
        dependency: Dependency
    ) {
        self.init(
            id: ReferenceIdentifier(id: state.id as AnyHashable),
            state: state,
            dependency: dependency
        )
    }
}

public extension Supervisor {
    /// Creates a supervisor with non-identifiable state.
    ///
    /// The supervisor's ``id`` is based on the feature type, meaning all supervisors
    /// of the same feature type share an identity. This is suitable for singleton
    /// features or when you don't need identity-based caching:
    ///
    /// ```swift
    /// struct AppFeature: FeatureProtocol {
    ///     struct State {
    ///         var isLoggedIn = false
    ///         var theme: Theme = .system
    ///     }
    ///     // ...
    /// }
    ///
    /// // Single app-level supervisor
    /// let appSupervisor = Supervisor<AppFeature>(
    ///     state: State(),
    ///     dependency: dependencies
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - state: The initial state.
    ///   - dependency: Dependencies for executing side effects.
    ///
    /// - Note: If your state conforms to `Identifiable`, the other initializer
    ///   is used automatically, deriving ID from `state.id`.
    convenience init(
        state: State,
        dependency: Dependency
    ) {
        self.init(
            id: ReferenceIdentifier(id: ObjectIdentifier(Supervisor<Feature>.self) as AnyHashable),
            state: state,
            dependency: dependency
        )
    }
}

extension Supervisor {
    private func processAsyncWork(_ work: Work<Action, Dependency>) async {
        switch work.operation {
        case .none:
            return

        case let .cancellation(id):
            await self.worker.cancel(taskID: id)
            return

        case .fireAndForget:
            Task {
                _ = await worker.run(work, using: dependency)
            }
            return

        case .task:
            let resultAction = await self.worker.run(work, using: self.dependency)

            if let resultAction {
                self.send(resultAction)
            }
            
        case .subscribe:
            // Start a detached task that iterates through the async sequence,
            // emitting each value as an action back to the supervisor
            Task { [weak self] in
                guard let self else { return }

                await self.worker.runSubscription(
                    work,
                    using: self.dependency,
                    onAction: { [weak self] action in
                        self?.send(action)
                    }
                )
            }
        }
    }
}
