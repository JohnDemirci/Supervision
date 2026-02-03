//
//  FeatureContainer.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import Observation
import OSLog

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
public final class Feature<F: FeatureBlueprint>: Observable {
    public typealias Action = F.Action
    public typealias Dependency = F.Dependency
    public typealias State = F.State

    public let id: ReferenceIdentifier

    let feature: F

    private let actionContinuation: AsyncStream<F.FeatureWork>.Continuation
    private let actionStream: AsyncStream<F.FeatureWork>
    private let dependency: Dependency
    private let worker: Worker<Action, Dependency>

    private nonisolated let logger: Logger

    private var processingTask: Task<Void, Never>?
    private var _state: State

    // MARK: - Initialization

    init(
        id: ReferenceIdentifier,
        state: State,
        dependency: Dependency
    ) {
        self.dependency = dependency
        self.worker = Worker()
        self.feature = F()
        self.id = id
        self.logger = .init(subsystem: "com.Supervision.\(F.self)", category: "Supervisor")
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

    @inline(__always)
    public subscript<T>(_ keyPath: KeyPath<State, T>) -> T {
        return _state[keyPath: keyPath]
    }

    @inline(__always)
    public func read<T>(_ keypath: KeyPath<State, T>) -> T {
        return _state[keyPath: keypath]
    }
}

// MARK: - Convenience Initializers

public extension Feature where State: Identifiable {
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

public extension Feature {
    convenience init(
        state: State,
        dependency: Dependency
    ) {
        self.init(
            id: ReferenceIdentifier(id: ObjectIdentifier(Feature<F>.self) as AnyHashable),
            state: state,
            dependency: dependency
        )
    }
}

extension Feature {
    /// Dispatches an action to be performed by the ``Feature``'s `Worker`
    ///
    /// - Parameters:
    ///    - action: Action to be performed
    public func send(_ action: Action) {
        let work: F.FeatureWork = withUnsafeMutablePointer(
            to: &_state
        ) { [self] pointer in
            let context = Context<F.State>(
                mutateFn: { @MainActor mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer)
            )

            return self.feature.process(action: action, context: context)
        }

        // we want to cancel in flight operations instead of waiting actionContinuation to finish finish
        if case .cancel = work.operation {
            Task { await worker.handle(work: work, environment: self.dependency, send: { _ in }) }
            return
        }

        actionContinuation.yield(work)
    }

    private func processAsyncWork(_ work: F.FeatureWork) async {
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

// MARK: - Feature + Direct Binding

extension Feature {
    func applyDirectMutation<Value>(keyPath: WritableKeyPath<State, Value>, value: Value) {
        _state[keyPath: keyPath] = value
    }

    @discardableResult
    func applyDirectMutation<Value: Equatable>(keyPath: WritableKeyPath<State, Value>, value: Value) -> Bool {
        let currentValue = _state[keyPath: keyPath]
        guard currentValue != value else { return false }

        _state[keyPath: keyPath] = value
        return true
    }
}

extension Feature where State: Identifiable {
    static func makeID(from id: State.ID) -> ReferenceIdentifier {
        ReferenceIdentifier(id, ObjectIdentifier(F.self))
    }
}
