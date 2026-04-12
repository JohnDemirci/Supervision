//
//  MergeInspection.swift
//  Supervision
//
//  Created by John Demirci on 4/11/26.
//

import Foundation
import IssueReporting

public final class MergeInspection<Action, Environment>: _Inspection {
    public typealias ChildInspection = RunInspection<Action, Environment>

    enum Event {
        case didComplete(AnyHashableSendable)
    }

    public typealias Action = Action
    public typealias Environment = Environment

    public let work: InspectedWork
    public var scope: InspectionScope { .concatenate }
    public let id: AnyHashableSendable

    var childInspections: [RunInspection<Action, Environment>] {
        didSet {
            if childInspections.isEmpty {
                sendEvent(.didComplete(id))
            }
        }
    }

    let originalNumberOfChildren: Int

    var toBeForgotten: Bool {
        didSet {
            childInspections.forEach {
                $0.forget()
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

    func handle(event: RunInspection<Action, Environment>.Event) {
        switch event {
        case .didComplete(let id):
            guard childInspections.count > 0 else {
                reportIssue("Attempting to remove an inspection when there is none")
                return
            }

            let index = childInspections.firstIndex(where: { $0.id == id })

            guard let index else {
                reportIssue("Attempting to remove an inspection when there is none")
                return
            }

            childInspections.remove(at: index)
        }
    }
}

extension MergeInspection {
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
