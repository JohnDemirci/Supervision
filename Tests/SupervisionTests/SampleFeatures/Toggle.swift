//
//  Toggle.swift
//  Supervision
//
//  Created by John Demirci on 4/19/26.
//

import Supervision

struct ToggleFeature: FeatureBlueprint {
    typealias Dependency = Void
    @ObservableValue
    struct State {
        var isToggled: Bool = false
    }

    enum Action {
        case toggle
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .toggle:
            context.isToggled.toggle()
        }

        return .done
    }
}
