//
//  Counter.swift
//  Supervision
//
//  Created by John Demirci on 4/19/26.
//

import Supervision

struct CounterFeature: FeatureBlueprint {
    typealias Dependency = Void

    @ObservableValue
    struct State {
        var counter: Int = 0
    }

    enum Action {
        case increment
        case decrement
    }

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
