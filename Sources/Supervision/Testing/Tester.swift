//
//  Tester.swift
//  Supervision
//
//  Created by John Demirci on 4/11/26.
//

import Foundation
import Combine

public final class Tester<Blueprint: FeatureBlueprint> {
    public typealias Action = Blueprint.Action
    public typealias Environment = Blueprint.Dependency
    public typealias State = Blueprint.State

    private let blueprint: Blueprint
    private var _state: State

    public let id: ReferenceIdentifier
    public var state: State {
        _read { yield _state }
    }

    let worker: TestWorker<Action, Environment>
    var cancellable: AnyCancellable?

    init(_state: State, id: ReferenceIdentifier) {
        self._state = _state
        self.id = id
        self.worker = .init()
        self.blueprint = .init()
    }
}

extension Tester {
    func send(
        _ action: Action,
        assertion: ((State) -> Void)? = nil
    ) -> any Inspection<Action, Environment> {
        let work = withUnsafeMutablePointer(to: &_state) { [self] pointer in
            let context = Context<State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: pointer,
                id: id
            )

            return blueprint.process(action: action, context: context)
        }

        assertion?(_state)

        let inspection = worker.register(work)

        return inspection
    }

    @discardableResult
    func feedResult<V>(
        _ result: Result<V, Error>,
        inspection: RunInspection<Action, Environment>,
        assertion: ((State) -> Void)? = nil
    ) -> any Inspection<Action, Environment> {
        send(
            worker.feedResult(result, for: inspection),
            assertion: assertion
        )
    }
}

extension Tester where State: Identifiable {
    public convenience init(initialState: State) {
        self.init(
            _state: initialState,
            id: Feature<Blueprint>.makeID(from: initialState.id)
        )
    }
}

extension Tester {
    public convenience init(initialState: State) {
        self.init(
            _state: initialState,
            id: Feature<Blueprint>.makeID()
        )
    }
}
