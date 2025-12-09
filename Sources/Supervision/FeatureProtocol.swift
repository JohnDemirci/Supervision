//
//  FeatureProtocol.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

@MainActor
public protocol FeatureProtocol {
    associatedtype State
    associatedtype Action: Sendable
    associatedtype Dependency: Sendable

    func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency>

    init()
}

/// Type-erased mutation that can be applied to state
@usableFromInline
struct AnyMutation<State> {
    var apply: (inout State) -> Void

    @usableFromInline
    init<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ value: Value
    ) {
        self.apply = { state in
            state[keyPath: keyPath] = value
        }
    }
}
