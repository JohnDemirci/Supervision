//
//  FeatureContainer.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import Observation
import OSLog
@_exported import ValueObservation

/// The source-of-truth owner for a feature's state, similar to stores in Redux and TCA.
///
/// ## Feature Identity ##
/// Each feature exposes a stable `id`. If `State` conforms to `Identifiable`, the identity combines
/// `state.id` with the feature type. Otherwise, the identity is based on the feature type alone.
///
/// ## Observation ##
/// ``Feature`` provides observation built on Swift's Observation framework while supporting value-type `State`.
/// Chained key-path reads (e.g. `\.some.nested.value`) notify observers only when that specific property changes.
///
/// ## Action Dispatch ##
/// ``Feature`` uses an `AsyncStream` to dispatch actions sequentially. Exceptions:
/// 1) cancellation ``Work`` is handled immediately instead of waiting in the queue, and
/// 2) subscriptions do not block the stream while they run.
///
/// Actions can be dispatched by calling the ``send(_:)`` function of the ``Feature``.
///
/// ## SwiftUI Bindings ##
/// ``Feature`` provides public APIs for SwiftUI bindings. More information can be found at
/// ``binding(_:send:animation:)``, ``directBinding(_:)``, and ``directBinding(_:animation:)``.
@MainActor
@dynamicMemberLookup
public final class Feature<F: FeatureBlueprint>: Observable {
    public typealias Action = F.Action
    public typealias Dependency = F.Dependency
    public typealias State = F.State

    public let id: ReferenceIdentifier

    let feature: F

    private let actionContinuation: AsyncStream<F.FeatureWork>.Continuation
    private let actionStream: AsyncStream<F.FeatureWork>
    private let dependency: Dependency!
    private let worker: Worker<Action, Dependency>

    private nonisolated let logger: Logger

    private var processingTask: Task<Void, Never>?

    #if DEBUG
    var previewActionMapper: ((Action) -> Action?)?
    #endif

    @usableFromInline
    @inline(__always)
    internal var _state: State

    // MARK: - Initialization

    #if DEBUG
    fileprivate init(
        id: ReferenceIdentifier,
        state: State
    ) {
        self.dependency = nil
        self.worker = Worker()
        self.feature = F()
        self.id = id
        self.logger = .init(subsystem: "com.Supervision.\(F.self)", category: "Feature.\(id)")
        self._state = state

        let (stream, continuation) = AsyncStream.makeStream(
            of: F.FeatureWork.self,
            bufferingPolicy: .unbounded
        )

        self.actionStream = stream
        self.actionContinuation = continuation

        self.processingTask = Task { [weak self] in
            for await work in stream {
                guard let self else { return }
                await self.processAsyncWork(work)
            }
        }

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
    }
    #endif

    init(
        id: ReferenceIdentifier,
        state: State,
        dependency: Dependency
    ) {
        self.dependency = dependency
        self.worker = Worker()
        self.feature = F()
        self.id = id
        self.logger = .init(subsystem: "com.Supervision.\(F.self)", category: "Feature.\(id)")
        self._state = state

        let (stream, continuation) = AsyncStream.makeStream(
            of: F.FeatureWork.self,
            bufferingPolicy: .unbounded
        )

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

    @inlinable
    @inline(__always)
    public var state: State {
        _read {
            yield self._state
        }
    }

    @inlinable
    @inline(__always)
    public subscript<Value>(dynamicMember member: KeyPath<State, Value>) -> Value {
        _read { yield state[keyPath: member] }
    }
}

// MARK: - Convenience Initializers

extension Feature where State: Identifiable {
    public convenience init(
        state: State,
        dependency: Dependency
    ) {
        self.init(
            id: Self.makeID(from: state.id),
            state: state,
            dependency: dependency
        )
    }

    public convenience init(
        state: State
    ) where Dependency == Void {
        self.init(
            id: Self.makeID(from: state.id),
            state: state,
            dependency: ()
        )
    }

    #if DEBUG
    internal convenience init(previewState: State) {
        self.init(id: Self.makeID(from: previewState.id), state: previewState)
    }
    #endif
}

extension Feature {
    public convenience init(
        state: State,
        dependency: Dependency
    ) {
        self.init(
            id: Self.makeID(),
            state: state,
            dependency: dependency
        )
    }

    public convenience init(
        state: State
    ) where Dependency == Void {
        self.init(
            id: Self.makeID(),
            state: state,
            dependency: ()
        )
    }

    #if DEBUG
    internal convenience init(previewState: State) {
        self.init(
            id: Self.makeID(),
            state: previewState
        )
    }
    #endif
}

extension Feature {
    /// Dispatches an action to be performed by the ``Feature``'s `Worker`
    ///
    /// - Parameters:
    ///    - action: Action to be performed
    public func send(_ action: Action) {
        #if DEBUG
        if let previewActionMapper = previewActionMapper, let mappedAction = previewActionMapper(action) {
            send(mappedAction)
            return
        }
        #endif

        let work: F.FeatureWork = withUnsafeMutablePointer(to: &_state) { [feature] pointer in
            feature.process(
                action: action,
                context: Context<F.State>(
                    statePointer: pointer,
                    id: id
                )
            )
        }

        // we want to cancel in flight operations instead of waiting actionContinuation to finish finish
        if case .cancel = work.operation {
            Task { await worker.handle(work: work, environment: dependency, send: { _ in }) }
            return
        }

        actionContinuation.yield(work)
    }

    private func processAsyncWork(_ work: F.FeatureWork) async {
        switch work.operation {
        case .done:
            return
        case .concatenate, .merge, .run, .cancel:
            await worker.handle(work: work, environment: dependency) { @MainActor [weak self] action in
                guard let self else { return }
                send(action)
            }
        }
    }
}

// MARK: - Feature + Direct Binding

extension Feature {
    @usableFromInline
    func applyDirectMutation<Value>(keyPath: WritableKeyPath<State, Value>, value: Value) {
        _state[keyPath: keyPath] = value
    }

    @discardableResult
    @usableFromInline
    func applyDirectMutation<Value: Equatable>(keyPath: WritableKeyPath<State, Value>, value: Value) -> Bool {
        let currentValue = _state[keyPath: keyPath]
        guard currentValue != value else { return false }
        _state[keyPath: keyPath] = value
        return true
    }
}

extension Feature where State: Identifiable {
    nonisolated static func makeID(from id: State.ID) -> ReferenceIdentifier {
        ReferenceIdentifier(id, ObjectIdentifier(F.self))
    }
}

extension Feature {
    nonisolated static func makeID() -> ReferenceIdentifier {
        ReferenceIdentifier(id: ObjectIdentifier(Feature<F>.self))
    }
}

extension Feature: @MainActor Equatable {
    public static func == (lhs: Feature<F>, rhs: Feature<F>) -> Bool {
        lhs === rhs
    }
}

extension Feature: @MainActor Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

#if DEBUG
extension Feature {
    public static func makePreview(
        state: State,
        previewActionMapper: ((Action) -> Action?)?
    ) -> Self {
        let feature = Self(previewState: state)
        feature.previewActionMapper = previewActionMapper
        return feature
    }
}
#endif
