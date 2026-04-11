//
//  DoneInspection.swift
//  Supervision
//
//  Created by John Demirci on 4/10/26.
//

import Foundation
import IssueReporting

public final class DoneInspection<Action, Environment>: _Inspection {
    enum Event {
        case didComplete(AnyHashableSendable)
    }

    public typealias Action = Action
    public typealias Environment = Environment

    public let work: InspectedWork
    public var scope: InspectionScope { .done }
    public let id = AnyHashableSendable(value: UUID())

    var didFinishAssertion: Bool = false
    var sendEvent: (Event) -> Void

    init(
        work: InspectedWork,
        sendEvent: @escaping (Event) -> Void
    ) {
        self.work = work
        self.sendEvent = sendEvent
    }

    deinit {
        if !self.didFinishAssertion {
            reportIssue("Did not dismiss `DoneInspection` before deallocation.")
        }
    }

    public func complete() {
        self.didFinishAssertion = true
        self.sendEvent(.didComplete(id))
    }
}
