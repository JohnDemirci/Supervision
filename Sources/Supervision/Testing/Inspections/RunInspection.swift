//
//  RunInspection.swift
//  Supervision
//
//  Created by John Demirci on 4/10/26.
//

import Foundation
import IssueReporting

public final class RunInspection<Action, Environment>: _Inspection {
    enum Event {
        case didComplete(AnyHashableSendable)
    }

    public typealias Action = Action
    public typealias Environment = Environment

    public let work: InspectedWork
    public let id: AnyHashableSendable

    public var scope: InspectionScope { .run }
    
    public var config: InspectedWork.RunConfiguration
    public var debounce: Duration? { config.debounce }
    public var throttle: Duration? { config.throttle }
    public var cancelInFlight: Bool { config.cancelInFlight }
    public var isSubscription: Bool { config.isSubscription }

    let testPlan: TestPlan<Action>
    let sendEvent: (Event) -> Void

    var didComplete: Bool = false {
        didSet {
            if didComplete { sendEvent(.didComplete(id)) }
        }
    }

    var toBeForgotten: Bool {
        didSet {
            if toBeForgotten {
                didComplete = true
            }
        }
    }

    init(work: InspectedWork, sendEvent: @escaping (Event) -> Void) {
        self.work = work
        var _id = AnyHashableSendable(value: UUID())
        self.sendEvent = sendEvent
        self.toBeForgotten = false

        guard case .run(let run) = work.operation else {
            fatalError()
        }

        if let cancelID = run.configuration.cancellationID {
            _id = cancelID
        }

        self.id = _id
        self.config = run.configuration

        guard let plan = run.testPlan else {
            fatalError()
        }

        self.testPlan = plan
    }

    deinit {
        if !isSubscription {
            guard didComplete else {
                reportIssue("deinitialized withut completing")
                return
            }
        }
    }

    func feedResult<V>(_ result: Result<V, Error>) -> Action {
        guard testPlan.kind == .task else {
            fatalError()
        }

        let actions = testPlan.feed(.taskResult(result))
        guard let action = actions.first else { fatalError() }
        didComplete = true
        return action
    }

    func feedValue<V>(_ value: V) -> Action {
        guard testPlan.kind == .stream else {
            fatalError()
        }

        let actions = testPlan.feed(.streamValues([value]))
        guard let action = actions.first else { fatalError() }
        return action
    }
}
