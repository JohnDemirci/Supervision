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
public protocol Composed: Sendable {
    associatedtype State: ObservableValue
    associatedtype Action
    associatedtype A: FeatureBlueprint
    associatedtype B: FeatureBlueprint

    var a: Feature<A> { get }
    var b: Feature<B> { get }

    func mapAction(_ action: Action) -> (A.Action?, B.Action?)
    func mapState() -> State
    func updateState(_ context: borrowing Context<State>)
}

extension Composed {
    func updateState(_ context: borrowing Context<State>) {
        context.state = mapState()
    }
}

struct CounterToggleComposition: Composed {
    @ObservableValue
    struct State {
        var counter: Int
        var isToggled: Bool

        init(counter: Int, isToggled: Bool) {
            self.counter = counter
            self.isToggled = isToggled
        }
    }

    enum Action {
        case increment
        case decrement
        case toggle
    }

    let a: Feature<CounterFeature>
    let b: Feature<ToggleFeature>

    func mapAction(_ action: Action) -> (CounterFeature.Action?, ToggleFeature.Action?) {
        switch action {
        case .increment:
            return (.increment, nil)
        case .decrement:
            return (.decrement, nil)
        case .toggle:
            return (nil, .toggle)
        }
    }

    func mapState() -> State {
        State(counter: a.counter, isToggled: b.isToggled)
    }

    func updateState(_ context: borrowing Context<State>) {
        context.counter = a.state.counter
        context.isToggled = b.state.isToggled
    }
}

@MainActor
@dynamicMemberLookup
public final class ComposedFeature<C: Composed>: Observable {
    public typealias State = C.State
    public typealias Action = C.Action

    let composed: C
    private var _state: State

    var state: State {
        _read { yield _state }
    }

    public subscript <Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<State, Subject>) -> Subject {
        _read { yield _state[keyPath: keyPath] }
    }

    init(composed: C) {
        self.composed = composed
        self._state = composed.mapState()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = composed.mapState()
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                withUnsafeMutablePointer(to: &_state) { pointer in
                    let context = Context(statePointer: pointer, id: ReferenceIdentifier(id: UUID()))
                    composed.updateState(context)
                }
                observe()
            }
        }
    }

    func send(_ action: Action) {
        let actions = composed.mapAction(action)

        if let aAction = actions.0 {
            composed.a.send(aAction)
        }
        
        if let bAction = actions.1 {
            composed.b.send(bAction)
        }
    }
}

struct CounterFeature: FeatureBlueprint {
    @ObservableValue
    struct State {
        var counter: Int = 0
    }

    enum Action {
        case increment
        case decrement
    }

    typealias Dependency = Void

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .increment:
            context.counter += 1
        case .decrement:
            context.counter -= 1
        }
        return .done
    }
}

struct ToggleFeature: FeatureBlueprint {
    @ObservableValue
    struct State {
        var isToggled: Bool = false
    }

    enum Action {
        case toggle
    }

    typealias Dependency = Void

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .toggle:
            context.isToggled.toggle()
        }
        return .done
    }
}
