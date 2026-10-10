//
//  Composed.swift
//  Supervision
//
//  Created by John Demirci on 4/18/26.
//

import Foundation
import Observation
import ValueObservation

/// A main-actor-isolated feature that derives its state and behavior from parent features.
///
/// Conforming types define how local actions are translated into parent actions and how
/// observable parent state is projected into local state.
@MainActor
public protocol Composed: Sendable {
    /// The observable state exposed by the composed feature.
    associatedtype State: ObservableValue

    /// The actions accepted by the composed feature.
    associatedtype Action: Sendable

    /// The parent features that provide the composed feature's state and behavior.
    associatedtype Parents: ParentFeaturesProtocol

    /// The parent features used by this composition.
    var parents: Parents { get }

    /// Translates a local action into actions for the parent features.
    ///
    /// - Parameter action: The local action to translate.
    /// - Returns: The corresponding actions to send to the parent features.
    func mapAction(_ action: Action) -> Parents.Actions

    /// Creates the composed feature's current state from its parent features.
    ///
    /// - Returns: The state derived from the current parent feature states.
    func mapState() -> State

    /// Updates the composed state after an observed parent value changes.
    ///
    /// - Parameter context: A borrowed context providing access to the state being updated.
    func updateState(context: borrowing Context<State>)
}

@MainActor
@dynamicMemberLookup
public final class ComposedFeature<C: Composed>: Observable {
    public typealias State = C.State
    public typealias Action = C.Action

    public let composed: C

    @usableFromInline
    internal var _state: State

    private let actionMapper: ((Action) -> C.Parents.Actions?)?
    private let isPreview: Bool

    #if DEBUG
    /// Creates a preview composition and optionally overrides how its actions
    /// are routed to the parent features.
    public static func preview(
        _ composed: C,
        actionMapper: ((Action) -> C.Parents.Actions)? = nil
    ) -> Self {
        Self(
            composed: composed,
            actionMapper: actionMapper
        )
    }

    private init(
        composed: C,
        actionMapper: ((Action) -> C.Parents.Actions?)? = nil
    ) {
        self.composed = composed
        self._state = composed.mapState()
        self.actionMapper = actionMapper
        self.isPreview = true
        observe()
    }
    #endif

    init(composed: C) {
        self.composed = composed
        self._state = composed.mapState()
        self.isPreview = false
        self.actionMapper = nil
        observe()
    }

    @inlinable
    @inline(__always)
    public var state: State {
        _read { yield _state }
    }

    @inlinable
    @inline(__always)
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        _read { yield _state[keyPath: keyPath] }
    }

    public func send(_ action: Action) {
        if isPreview {
            if let actions = actionMapper?(action) {
                composed.parents.send(actions)
                return
            }
        }

        composed.parents.send(composed.mapAction(action))
    }
}

private extension ComposedFeature {
    func observe() {
        withObservationTracking {
            _ = composed.mapState()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                withUnsafeMutablePointer(to: &_state) { pointer in
                    composed.updateState(
                        context: Context(statePointer: pointer)
                    )
                }
                observe()
            }
        }
    }
}

extension ComposedFeature: @MainActor Equatable {
    public static func == (lhs: ComposedFeature<C>, rhs: ComposedFeature<C>) -> Bool {
        lhs === rhs
    }
}

extension ComposedFeature: @MainActor Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
