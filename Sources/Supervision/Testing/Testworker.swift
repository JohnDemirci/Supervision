//
//  Testworker.swift
//  Supervision
//
//  Created by John Demirci on 4/9/26.
//

import Foundation
import IssueReporting
import Combine

final class TestWorker<Action, Environment> {
    enum WorkerAction {
        case doneInspectionEvent(DoneInspection<Action, Environment>.Event)
        case cancelInspectionEvent(CancelInspection<Action, Environment>.Event)
        case runInspectionEvent(RunInspection<Action, Environment>.Event)
        case concatenateInspectionEvent(ConcatenateInspection<Action, Environment>.Event)
        case mergeInspectionEvent(MergeInspection<Action, Environment>.Event)
    }

    private var queue: [any Inspection<Action, Environment>] = []
    private var subscriptionQueue: [RunInspection<Action, Environment>] = []

    deinit {
        guard queue.isEmpty else {
            reportIssue("queue is not empty on deinit: \(queue)")
            return
        }
    }

    @discardableResult
    func register(_ work: Work<Action, Environment>) -> any Inspection<Action, Environment> {
        let inspection: any Inspection<Action, Environment> = switch work.operation {
        case .done:
            DoneInspection(work: work) { [weak self] event in
                self?.handleAction(.doneInspectionEvent(event))
            }
        case .cancel:
            CancelInspection(work: work) { [weak self] event in
                self?.handleAction(.cancelInspectionEvent(event))
            }
        case .run(let run):
            RunInspection(work: work) { [weak self] event in
                self?.handleAction(.runInspectionEvent(event))
            }
        case .merge:
            MergeInspection(work: work) { [weak self] event in
                self?.handleAction(.mergeInspectionEvent(event))
            }
        case .concatenate:
            ConcatenateInspection(work: work) { [weak self] event in
                self?.handleAction(.concatenateInspectionEvent(event))
            }
        }

        let existingInspectionIndex = self.queue.firstIndex {
            $0.id == inspection.id
        }

        let existingSubscriptionIndex = self.queue.firstIndex {
            $0.id == inspection.id
        }

        if let existingInspectionIndex {
            if let existingInspection = queue[existingInspectionIndex] as? RunInspection<Action, Environment> {
                if existingInspection.cancelInFlight {
                    queue.remove(at: existingInspectionIndex)
                } else {
                    return existingInspection
                }
            }
        }

        if let existingSubscriptionIndex {
            if let existingInspection = queue[existingSubscriptionIndex] as? RunInspection<Action, Environment> {
                if existingInspection.cancelInFlight {
                    subscriptionQueue.remove(at: existingSubscriptionIndex)
                } else {
                    return existingInspection
                }
            }
        }

        if case .run = inspection.scope {
            guard let x = inspection as? RunInspection<Action, Environment> else {
                fatalError()
            }

            if x.isSubscription {
                subscriptionQueue.append(x)
                return inspection
            } else if x.config.fireAndForget {
                return inspection
            }
        }

        queue.append(inspection)
        return inspection
    }

    func handleAction(_ action: WorkerAction) {
        switch action {
        case .doneInspectionEvent(let event):
            handleDoneInspectionEvent(event)

        case .cancelInspectionEvent(let event):
            handleCancelInspectionEvent(event)

        case .runInspectionEvent(let event):
            handleRunInspectionEvent(event)

        case .concatenateInspectionEvent(let event):
            handleConcatenateInspectionEvent(event)

        case .mergeInspectionEvent(let event):
            handleMergeInspectionEvent(event)
        }
    }

    func feedResult<V>(
        _ result: Result<V, Error>,
        for inspection: RunInspection<Action, Environment>
    ) -> Action {
        inspection.feedResult(result)
    }

    func feedValue<V>(
        _ value: V,
        for inspection: RunInspection<Action, Environment>
    ) -> Action {
        inspection.feedValue(value)
    }
}

private extension TestWorker {
    func handleDoneInspectionEvent(_ event: DoneInspection<Action, Environment>.Event) {
        switch event {
        case .didComplete(let id):
            let inspection = queue.removeLast()

            guard inspection.id == id else {
                reportIssue("mismatching ids")
                return
            }
        }
    }

    func handleCancelInspectionEvent(_ event: CancelInspection<Action, Environment>.Event) {
        switch event {
        case .cancellationStarted(canceler: let cancellerID, cancellee: let cancelleeID):
            let inspection = queue.removeLast() as? CancelInspection<Action, Environment>

            guard inspection?.id == cancellerID else {
                reportIssue()
                return
            }

            var didFound = false

            for (index, inspection) in queue.enumerated() {
                switch inspection.work.operation {
                case .done, .cancel:
                    continue
                case .run:
                    if inspection.id == cancelleeID {
                        didFound = true

                        let x = inspection.assertRun()
                        x.didComplete = true
                        break
                    }
                case .concatenate:
                    let concreteInspection = inspection.assertConcatenate()

                    let childIndex = concreteInspection.childInspections.firstIndex {
                        $0.id == cancelleeID
                    }

                    guard childIndex != nil else { continue }

                    didFound = true

                    for childInspection in concreteInspection.childInspections {
                        childInspection.didComplete = true
                    }

                    concreteInspection.childInspections.removeAll()
                    break

                case .merge:
                    let concreteInspection = inspection.assertMerge()

                    let childIndex = concreteInspection.childInspections.firstIndex {
                        $0.id == cancelleeID
                    }

                    guard childIndex != nil else { continue }

                    didFound = true

                    for childInspection in concreteInspection.childInspections {
                        childInspection.didComplete = true
                    }

                    concreteInspection.childInspections.removeAll()
                }
            }
            if !didFound {
                for (index, inspection) in subscriptionQueue.enumerated() {
                    if inspection.id == cancelleeID {
                        didFound = true
                        inspection.didComplete = true
                        break
                    }
                }
            }

            guard didFound else {
                reportIssue("Could not find the target inspection to cancel")
                return
            }
        }
    }

    func handleRunInspectionEvent(_ event: RunInspection<Action, Environment>.Event) {
        switch event {
        case .didComplete(let id):
            queue.removeAll { $0.id == id }
        }
    }

    func handleConcatenateInspectionEvent(_ event: ConcatenateInspection<Action, Environment>.Event) {
        switch event {
        case .didComplete(let id):
            queue.removeAll { $0.id == id }
        }
    }

    func handleMergeInspectionEvent(_ event: MergeInspection<Action, Environment>.Event) {
        switch event {
        case .didComplete(let id):
            queue.removeAll { $0.id == id }
        }
    }
}
