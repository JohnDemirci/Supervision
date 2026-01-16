//
//  Supervisor.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import Observation
import OSLog

@MainActor
public final class Supervisor<Feature: FeatureProtocol>: Observable {
    public typealias Action = Feature.Action
    public typealias Dependency = Feature.Dependency
    public typealias State = Feature.State

    public let id: ReferenceIdentifier

    let feature: Feature

    private nonisolated let logger: Logger

    private let actionContinuation: AsyncStream<Feature.FeatureWork>.Continuation
    private let actionStream: AsyncStream<Feature.FeatureWork>
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
    private let worker: Worker<Action, Dependency>

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
            of: Feature.FeatureWork.self,
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
     it looks like the observation does not work correctly with dynamic member lookup when we are observing nested keypaths.
     
     from what i gathered it looks like the compiler cannot determine that at sn optimized level and therefore ignore it it only viewed as the parent keypath not the nested ones so when a child keypath gets updated the parent is not being updated
     
     to negate this behavior instead of using dynamic member lookup we are going to be using a custom function and custom subscript.
     
     from the limited testing it looks like the view is updating correctly

     \.state.person.name
     */

    @inline(__always)
    public subscript<T>(_ keyPath: KeyPath<State, T>) -> T {
        trackAccess(for: keyPath)
        return _state[keyPath: keyPath]
    }

    @inline(__always)
    public func read<T>(_ keypath: KeyPath<State, T>) -> T {
        trackAccess(for: keypath)
        return _state[keyPath: keypath]
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
            id: Self.makeID(from: state.id),
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
    public func send(_ action: Action) {
        // Note: [weak self] is not needed here because this closure is non-escaping.
        // Although Context stores an @escaping closure (mutateFn), the Context itself
        // is borrowed (not stored) by feature.process() and is deallocated when this
        // method returns. The strong capture of self is scoped to this synchronous call.

        /*
         Using an unsafePointer is safe here because the Context cannot escape the scope of the closre due to the fact that Context is ~Copyable.
         Because it cannot outlive the scope of this closure, there is no risk of dangling pointers.
         */
        let work: Feature.FeatureWork = withUnsafeMutablePointer(
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

        // we want to cancel in flight operations instead of waiting actionContinuation to finish finish
        if case .cancel = work.operation {
            Task {
                await worker.handle(work: work, environment: self.dependency, send: { _ in })
            }
            return
        }

        actionContinuation.yield(work)
    }

    private func processAsyncWork(_ work: Feature.FeatureWork) async {
        switch work.operation {
        case .done:
            return
        default:
            await worker.handle(work: work, environment: dependency) { @MainActor [weak self] action in
                guard let self else { return }
                send(action)
            }
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

extension Supervisor where State: Identifiable {
    static func makeID(from id: State.ID) -> ReferenceIdentifier {
        ReferenceIdentifier(id, ObjectIdentifier(Feature.self))
    }
}
