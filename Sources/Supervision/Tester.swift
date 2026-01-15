//
//  Tester.swift
//  Supervision
//
//  Created by John Demirci on 1/9/26.
//

import Foundation
import OSLog

@MainActor
@dynamicMemberLookup
public final class Tester<Feature: FeatureProtocol> {
    public typealias Action = Feature.Action
    public typealias Dependency = Feature.Dependency
    public typealias State = Feature.State

    let feature: Feature
    private nonisolated let logger: Logger
    private var _state: State

    init(state: State) {
        self.feature = .init()
        self.logger = Logger(subsystem: "Test", category: "Tester<\(Feature.self)>")
        self._state = state
    }

    public subscript<Subject>(
        dynamicMember keyPath: KeyPath<State, Subject>
    ) -> Subject {
        return _state[keyPath: keyPath]
    }

    func send(_ action: Action) {
        let work: Feature.FeatureWork = withUnsafeMutablePointer(
            to: &_state
        ) { [self] pointer in
            let context = Context<Feature.State>(
                mutateFn: { @MainActor mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer)
            )

            return self.feature.process(action: action, context: context)
        }
    }
}
