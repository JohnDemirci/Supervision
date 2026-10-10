//
//  DashboardComposition.swift
//  Supervision
//
//  Created by John Demirci on 4/20/26.
//

import Supervision

struct DashboardComposition: Composed {
    typealias Parents = ParentFeatures<CounterFeature, ToggleFeature>

    @ObservableValue
    struct State {
        var count: Int
        var isEnabled: Bool
    }

    enum Action: Sendable {
        case increment
        case toggle
        case synchronize
    }

    let parents: Parents

    func mapAction(_ action: Action) -> Parents.Actions {
        switch action {
        case .increment:
            (.increment, nil)
        case .toggle:
            (nil, .toggle)
        case .synchronize:
            (.increment, .toggle)
        }
    }

    func mapState() -> State {
        parents.withFeatures { counter, toggle in
            State(
                count: counter.counter,
                isEnabled: toggle.isToggled
            )
        }
    }

    func updateState(context: borrowing Context<State>) {
        parents.withFeatures { counter, toggle in
            context.count = counter.counter
            context.isEnabled = toggle.isToggled
        }
    }
}
