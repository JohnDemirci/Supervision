//
//  Composed.swift
//  Supervision
//
//  Created by John Demirci on 4/18/26.
//

import Foundation
import Observation
import ValueObservation

@MainActor
public protocol ParentFeaturesProtocol: Sendable {
    associatedtype Actions

    func send(_ actions: Actions)
}

@MainActor
public struct ParentFeatures<each Blueprint: FeatureBlueprint>: ParentFeaturesProtocol, Sendable
where
    repeat each Blueprint: FeatureBlueprint
{
    public typealias Actions = (repeat ((each Blueprint).Action?))

    @usableFromInline
    let features: (repeat Feature<each Blueprint>)

    public init(_ features: repeat Feature<each Blueprint>) {
        self.features = (repeat each features)
    }

    public func withFeatures<Result>(
        _ body: (repeat Feature<each Blueprint>) -> Result
    ) -> Result {
        body(repeat each features)
    }

    public func send(_ actions: Actions) {
        repeat route((each actions), to: (each features))
    }

    private func route<F: FeatureBlueprint>(
        _ action: F.Action?,
        to feature: Feature<F>
    ) {
        guard let action else { return }
        feature.send(action)
    }
}

@MainActor
public protocol Composed: Sendable {
    associatedtype State: ObservableValue
    associatedtype Action: Sendable
    associatedtype Parents: ParentFeaturesProtocol

    var parents: Parents { get }

    func mapAction(_ action: Action) -> Parents.Actions
    func mapState() -> State
    func updateState(_ state: inout State)
}

public extension Composed {
    func updateState(_ state: inout State) {
        state = mapState()
    }
}

@MainActor
@dynamicMemberLookup
public final class ComposedFeature<C: Composed>: Observable {
    public typealias State = C.State
    public typealias Action = C.Action

    public let composed: C

    @usableFromInline
    internal var _state: State

    public init(composed: C) {
        self.composed = composed
        self._state = composed.mapState()
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
                composed.updateState(&_state)
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
