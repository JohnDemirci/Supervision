//
//  FeatureProtocol.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

public protocol FeatureProtocol {
    typealias FeatureWork = Work<Action, Dependency>
    typealias ObservationMap = [PartialKeyPath<State>: [PartialKeyPath<State>]]

    associatedtype State: Equatable
    associatedtype Action: Sendable
    associatedtype Dependency: Sendable

    var observationMap: ObservationMap { get }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork

    init()
}

extension FeatureProtocol {
    public var observationMap: ObservationMap {
        [:]
    }
}

@usableFromInline
struct AnyMutation<State> {
    @usableFromInline
    let keyPath: PartialKeyPath<State>

    @usableFromInline
    var apply: (inout State) -> Void

    @usableFromInline
    init<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ value: Value
    ) {
        self.keyPath = keyPath
        self.apply = { state in
            state[keyPath: keyPath] = value
        }
    }
}
