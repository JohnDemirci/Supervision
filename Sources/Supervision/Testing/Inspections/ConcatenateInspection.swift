//
//  ConcatenateInspection.swift
//  Supervision
//
//  Created by John Demirci on 4/11/26.
//

import Foundation
import IssueReporting

public final class ConcatenateInspection<Action, Environment>: _Inspection {
    typealias ChildInspection = RunInspection<Action, Environment>

    enum Event {
        case didComplete(AnyHashableSendable)
    }

    public typealias Action = Action
    public typealias Environment = Environment

    public let work: InspectedWork
    public var scope: InspectionScope { .concatenate }
    public let id: AnyHashableSendable
    let originalNumberOfChildren: Int

    var toBeForgotten: Bool {
        didSet {
            if toBeForgotten {
                childInspections.forEach { $0.forget() }
            }
        }
    }

    var childInspections: [RunInspection<Action, Environment>] {
        didSet {
            if childInspections.isEmpty {
                sendEvent(.didComplete(id))
            }
        }
    }

    let sendEvent: (Event) -> Void

    init(
        work: InspectedWork,
        sendEvent: @escaping (Event) -> Void
    ) {
        self.work = work
        self.id = AnyHashableSendable(value: UUID())
        self.childInspections = []
        self.sendEvent = sendEvent
        self.toBeForgotten = false

        guard case .concatenate(let children) = work.operation else {
            fatalError()
        }

        self.originalNumberOfChildren = children.count

        self.childInspections = children.map {
            RunInspection(work: $0) { [weak self] event in
                self?.handle(event: event)
            }
        }
    }

    deinit {
        guard childInspections.isEmpty else {
            reportIssue("deinitializing while children remain")
            return
        }
    }

    func handle(event: RunInspection<Action, Environment>.Event) {
        switch event {
        case .didComplete(let id):
            guard childInspections.count > 0 else {
                reportIssue("Attempting to remove an inspection when there is none")
                return
            }

            let currentInspection = childInspections.first

            guard currentInspection?.id == id else {
                reportIssue("out of order inspection detected")
                return
            }

            childInspections.removeFirst()
        }
    }
}

extension ConcatenateInspection {
    func children() -> (ChildInspection, ChildInspection) {
        guard originalNumberOfChildren == 2 else {
            preconditionFailure("number of children do not match")
        }

        return (childInspections[0], childInspections[1])
    }

    func children() -> (ChildInspection, ChildInspection, ChildInspection) {
        guard originalNumberOfChildren == 3 else {
            preconditionFailure("number of children do not match")
        }

        return (childInspections[0], childInspections[1], childInspections[2])
    }

    func children() -> (ChildInspection, ChildInspection, ChildInspection, ChildInspection) {
        guard originalNumberOfChildren == 4 else {
            preconditionFailure("number of children do not match")
        }

        return (childInspections[0], childInspections[1], childInspections[2], childInspections[3])
    }

    func children() -> (ChildInspection, ChildInspection, ChildInspection, ChildInspection, ChildInspection) {
        guard originalNumberOfChildren == 5 else {
            preconditionFailure("number of children do not match")
        }

        return (childInspections[0], childInspections[1], childInspections[2], childInspections[3], childInspections[4])
    }
}
