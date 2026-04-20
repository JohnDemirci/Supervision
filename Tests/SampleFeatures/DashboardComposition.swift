//
//  DashboardComposition.swift
//  Supervision
//
//  Created by John Demirci on 4/20/26.
//

import Supervision

@ObservableValue
struct DashboardState {
    var count: Int
    var isEnabled: Bool
}

struct DashboardComposition: Composed {
    enum Action: Sendable {
        case increment
        case setEnabled(Bool)
        case synchronize
    }

    typealias State = DashboardState
    typealias Parents = ParentFeatures<CounterFeature, ToggleFeature>

    let parents: Parents

    func mapAction(_ action: Action) -> Parents.Actions {
        switch action {
        case .increment:
            (.increment, nil)
        case .setEnabled(let value):
            (nil, .setEnabled(value))
        case .synchronize:
            (.increment, .setEnabled(true))
        }
    }

    func mapState() -> State {
        parents.withFeatures { counter, toggle in
            DashboardState(
                count: counter.count,
                isEnabled: toggle.isEnabled
            )
        }
    }

    func updateState(context: borrowing Context<State>) {
        parents.withFeatures { counter, toggle in
            context.count = counter.count
            context.isEnabled = toggle.isEnabled
        }
    }
}
