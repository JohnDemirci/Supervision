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
    
    init(count: Int, isEnabled: Bool) {
        self.count = count
        self.isEnabled = isEnabled
    }
}

struct DashboardComposition: Composed {
    enum Action: Sendable {
        case increment
        case toggle
        case synchronize
    }

    typealias State = DashboardState
    typealias Parents = ParentFeatures<CounterFeature, ToggleFeature>

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
            DashboardState(
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
