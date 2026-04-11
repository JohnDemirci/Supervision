//
//  CancelInspection.swift
//  Supervision
//
//  Created by John Demirci on 4/10/26.
//

import Foundation
import IssueReporting

public final class CancelInspection<Action, Environment>: _Inspection {
    enum Event {
        case cancellationStarted(canceler: AnyHashableSendable, cancellee: AnyHashableSendable)
    }

    public typealias Action = Action
    public typealias Environment = Environment

    public let work: InspectedWork
    public var scope: InspectionScope { .cancel }
    public let id: AnyHashableSendable

    let sendEvent: (Event) -> Void

    init(work: InspectedWork, sendEvent: @escaping (Event) -> Void) {
        self.work = work
        self.id = AnyHashableSendable(value: UUID())
        self.sendEvent = sendEvent
    }

    func startCancellation() {
        guard case .cancel(let cancelID) = work.operation else {
            reportIssue("wrong operation")
            return
        }

        sendEvent(.cancellationStarted(canceler: id, cancellee: cancelID))
    }
}
