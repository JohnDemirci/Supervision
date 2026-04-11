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
    }

    private var queue: [any Inspection<Action, Environment>] = []
    private let subject = PassthroughSubject<Action, Never>()

    var publisher: AnyPublisher<Action, Never> {
        subject.eraseToAnyPublisher()
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
        case .run:
            RunInspection(work: work) { [weak self] event in
                self?.handleAction(.runInspectionEvent(event))
            }
        case .merge:
            MergeInspection(work: work)
        case .concatenate:
            ConcatenateInspection(work: work)
        }

        self.queue.append(inspection)

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
        }
    }

    func feedResult<V>(
        _ result: Result<V, Error>,
        for inspection: RunInspection<Action, Environment>
    ) -> Action {
        inspection.feedResult(result)
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
            let inspection = queue.removeLast()
                .assertCancel()

            guard inspection.id == cancellerID else {
                reportIssue()
                return
            }

            let index = queue.firstIndex { $0.id == cancelleeID }

            guard let index else { return }

            switch queue[index].scope {
            case .run:
                let runInspection = queue[index].assertRun()
                runInspection.didComplete = true
                queue.remove(at: index)
            case .concatenate:
                let concatenateInspection = queue[index].assertConcatenate()
            case .merge:
                let mergeInspection = queue[index].assertMerge()
            default:
                fatalError("unexpected scope")
            }
        }
    }

    func handleRunInspectionEvent(_ event: RunInspection<Action, Environment>.Event) {
        switch event {
        case .didFeed(let id, let action):
            subject.send(action)
        }
    }
}

public final class ConcatenateInspection<Action, Environment>: _Inspection {
    public typealias Action = Action
    public typealias Environment = Environment

    public let work: InspectedWork
    public var scope: InspectionScope { .concatenate }

    init(work: InspectedWork) {
        self.work = work
    }
}

public final class MergeInspection<Action, Environment>: _Inspection {
    public typealias Action = Action
    public typealias Environment = Environment

    public let work: InspectedWork
    public var scope: InspectionScope { .merge }

    init(work: InspectedWork) {
        self.work = work
    }
}

