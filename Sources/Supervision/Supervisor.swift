//
//  Supervisor.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import Observation
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
/// ## Granular Observation
///
/// Views only re-render when the specific properties they access change:
///
/// ```swift
/// // This view only re-renders when `count` changes
/// struct CounterView: View {
///     let supervisor: Supervisor<MyFeature>
///     var body: some View {
///         Text("\(supervisor.count)")  // Tracks only \.count
///     }
/// }
///
/// // This view only re-renders when `name` changes
/// struct NameView: View {
///     let supervisor: Supervisor<MyFeature>
///     var body: some View {
///         Text(supervisor.name)  // Tracks only \.name
///     }
/// }
///
/// // Mutating count does NOT re-render NameView
/// supervisor.send(.incrementCount)
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
@dynamicMemberLookup
public final class Supervisor<Feature: FeatureProtocol>: Observable {
    public typealias Action = Feature.Action
    public typealias CancellationID = Feature.CancellationID
    public typealias Dependency = Feature.Dependency
    public typealias State = Feature.State

    public let id: ReferenceIdentifier

    let feature: Feature

    private nonisolated let logger: Logger

    private let actionContinuation: AsyncStream<Work<Action, Dependency, CancellationID>>.Continuation
    private let actionStream: AsyncStream<Work<Action, Dependency, CancellationID>>
    private let dependency: Dependency

    /*
     one of the shorcomings of the observation mechanism is that computed properties are not notified when a keypath that they are observing changes.

     in oder to address this issue, client needs to provide a map of dependencies for the computed properties where they provide a list of keypaths they want the computed property to be associated to.

     when those provided keypaths mutate, we fire off notification for the computed properties observation token
     */
    private let observationMap: Feature.ObservationMap

    /*
     A Seperate entity is responsible for handling async operations

     I did not want to add too many responsibilities onto Supervisor.
     Worker is an actor that performs the Side effects and returns the results to the Supervisor
     */
    private let worker: Worker<Action, Dependency, CancellationID>

    /*
     sequentially handling async work

     this is a state management architecture and by design, all async work is done sequentially. There are some exceptions such as FireAndForget.
     */
    private var processingTask: Task<Void, Never>?

    /*
     Observation tokens are reference types that are marcked with the @Observable notation
     Each keypath of the Supervisor's State contains ObservationToken upon first access via the dynamicMember subscript
     When a mutation occurs for a particular keypath, the observation token's version is incremented to notify the mutation.
     This observation mechanism is implemented due to shortcomings of the @Observable macro where @Observable cannot be used on Value types (struct & enum)
     We could annotate the Supervisor itself as @Observable, but it would fire mutation notifications even when the client is not observing the notifying keypath resulting in excessive SwiftUI re-draws.
     We could create our own macro similar to TCA's @ObservableState but that would involve having to import SwiftSyntax library as well as the complexity of maintaining the macro not to mention added build times on fresh builds. Therefore i went with this manual implementation where each keypath of a value type has an ObservationToken, technically these tokens are observed but whenever a keypath is modified we increment the token to notify the observer.
     This achieves per-keypath view re-draw for switftui.
     */
    private var _observationTokens: [PartialKeyPath<State>: ObservationToken] = [:]

    /*
     Purpusefully left as private.
     The observation system works through keypath basis
     therefore accessing the _state directly does not track/notify observers.
     Additionally, one of the principles of this architecture is that mutation happens internally (SwiftUI Binding is the exception)
     The mutations must occure in the FeatureProtocol and the helper APIs from the Context<State> this is done in order to make the mutations of the state more predictable.
     Access to the _state can happen multiple ways.

     1) Through Context<State> from FeatureProtocol's process function
        This function is triggered when the client sends an Action to the Supervisor
     2) dynamicMember subscript
        Accessing the state through subscript is what triggers the Observation mechanism of this architecture.
     */
    private var _state: State

    // MARK: - Initialization

    init(
        id: ReferenceIdentifier,
        state: State,
        dependency: Dependency
    ) {
        self.dependency = dependency
        self.worker = Worker()
        self.feature = Feature()
        self.id = id
        self.logger = .init(subsystem: "com.Supervision.\(Feature.self)", category: "Supervisor")
        self._state = state

        let (stream, continuation) = AsyncStream.makeStream(
            of: Work<Action, Dependency, CancellationID>.self,
            bufferingPolicy: .unbounded
        )

        // reverse the observationMap provided by the feature
        // this makes it easier to notify the changes
        self.observationMap = feature.observationMap.reduce(
            into: Feature.ObservationMap()
        ) { partialResult, kvp in
            kvp.value.forEach { valueKeypath in
                partialResult[valueKeypath, default: []].append(kvp.key)
            }
        }

        self.actionStream = stream
        self.actionContinuation = continuation

        self.processingTask = Task { [weak self] in
            for await work in stream {
                guard let self else { return }
                await self.processAsyncWork(work)
            }
        }

        #if DEBUG
        let mirror = Mirror(reflecting: state)
        if mirror.displayStyle != .struct {
            logger.error(
                """
                Warning: State should be a struct (value type).
                Using reference types (classes) can lead to unexpected behavior.
                Current State type: \(type(of: state))
                """
            )
        }
        #endif
    }

    isolated deinit {
        actionContinuation.finish()
        processingTask?.cancel()
        processingTask = nil
    }

    /*
     this is the public public which consumers of this architecture use to access the state amd enable observation.

     trackAccess(for: keyPath) function references a class annotated with the @Observable macro

     when a swiftui view is accessing the keypath, the observvation machinery in swiftui and the observation framework sees that there's an interaction with an @Observable class, in this case, it is the ObservationToken.

     _ = token(for: keyPath).version

     when swiftui's body re-evaluate, it checks if the version number corresponding to the keypath changes.

     in a way the current implementation is similar to doing something like this

     withObservationTracking {
         _ = token(for: keyPath).version
     } onChange: {
         ...
     }

     because that particular keypath is associated with the observation token, the mutation notifications for the keypath will cause the re-render
     */
    public subscript<Subject>(dynamicMember keyPath: KeyPath<State, Subject>) -> Subject {
        trackAccess(for: keyPath)
        return _state[keyPath: keyPath]
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

// MARK: - Observation

extension Supervisor {
    @inline(__always)
    private func token(for keyPath: PartialKeyPath<State>) -> ObservationToken {
        if let existing = _observationTokens[keyPath] {
            return existing
        }
        let newToken = ObservationToken()
        _observationTokens[keyPath] = newToken
        return newToken
    }

    @inline(__always)
    private func trackAccess<Value>(for keyPath: KeyPath<State, Value>) {
        _ = token(for: keyPath).version
    }

    @inline(__always)
    private func notifyChange(for keyPath: PartialKeyPath<State>) {
        _observationTokens[keyPath]?.increment()

        if let computedPropertyKeypaths = observationMap[keyPath] {
            computedPropertyKeypaths.forEach { computedPropertyKeypath in
                _observationTokens[computedPropertyKeypath]?.increment()
            }
        }
    }
}

extension Supervisor {
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
        // Note: [weak self] is not needed here because this closure is non-escaping.
        // Although Context stores an @escaping closure (mutateFn), the Context itself
        // is borrowed (not stored) by feature.process() and is deallocated when this
        // method returns. The strong capture of self is scoped to this synchronous call.

        /*
         Using an unsafePointer is safe here because the Context cannot escape the scope of the closre due to the fact that Context is ~Copyable.
         Because it cannot outlive the scope of this closure, there is no risk of dangling pointers.
         */
        let work: Work<Action, Dependency, CancellationID> = withUnsafeMutablePointer(
            to: &_state
        ) { [self] pointer in
            let context = Context<Feature.State>(
                mutateFn: { @MainActor mutation in
                    mutation.apply(&pointer.pointee)
                    self.notifyChange(for: mutation.keyPath)

                    #if DEBUG
                    self.logger.debug("\(mutation.keyPath.debugDescription) has changed")
                    #endif
                },
                statePointer: UnsafePointer(pointer)
            )

            return self.feature.process(action: action, context: context)
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

    private func processAsyncWork(_ work: Work<Action, Dependency, CancellationID>) async {
        switch work.operation {
        case .none:
            return

        case let .cancellation(id):
            await self.worker.cancel(taskID: id)

        case .fireAndForget:
            Task { _ = await worker.run(work, using: dependency) }

        case .task:
            let resultAction = await self.worker.run(work, using: self.dependency)

            if let resultAction {
                self.send(resultAction)
            }

        case .subscribe:
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

// MARK: - Supervisor + Direct Binding

extension Supervisor {
    /// Applies a mutation directly to the state for a specific keyPath.
    /// Used internally by `directBinding` for direct state mutations.
    func applyDirectMutation<Value>(keyPath: WritableKeyPath<State, Value>, value: Value) {
        _state[keyPath: keyPath] = value
        notifyChange(for: keyPath)
    }

    @discardableResult
    func applyDirectMutation<Value: Equatable>(keyPath: WritableKeyPath<State, Value>, value: Value) -> Bool {
        let currentValue = _state[keyPath: keyPath]
        guard currentValue != value else { return false }

        _state[keyPath: keyPath] = value
        notifyChange(for: keyPath)
        return true
    }
}

@Observable
final class ObservationToken: @unchecked Sendable {
    var version: Int = 0

    func increment() {
        version += 1
    }
}
