//
//  Tester.swift
//  Supervision
//
//  Created by John Demirci on 1/9/26.
//

import Foundation
import OSLog
import IssueReporting

@MainActor
@dynamicMemberLookup
public final class Tester<F: FeatureBlueprint> {
    enum Failure: Error, CustomStringConvertible {
        case message(String)

        var description: String {
            switch self {
            case .message(let message):
                return message
            }
        }
    }

    public typealias Action = F.Action
    public typealias Dependency = F.Dependency
    public typealias State = F.State

    let F: F
    private var _state: State
    let id: ReferenceIdentifier

    private var inspectionList: Set<WorkInspection<F>> = []

    isolated deinit {
        if !inspectionList.isEmpty {
            reportIssue("pending inspections: \(inspectionList)")
        }
    }

    init(state: State, id: ReferenceIdentifier) {
        self.F = .init()
        self._state = state
        self.id = id
    }

    public subscript<Subject>(
        dynamicMember keyPath: KeyPath<State, Subject>
    ) -> Subject {
        return _state[keyPath: keyPath]
    }

    public func feedResult<Value>(
        for inspection: WorkInspection<F>,
        result: Result<Value, Error>,
        assertion: (State) -> Void
    ) throws -> WorkInspection<F> {
        inspection.assertRun()
        let action = try inspection.feedResult(result)
        return send(action, assertion: assertion)
    }

    public func send(
        _ action: Action,
        assertion: (State) -> Void = { _ in }
    ) -> WorkInspection<F> {
        let work: F.FeatureWork = withUnsafeMutablePointer(
            to: &_state
        ) { [self] pointer in
            let context = Context<F.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer),
                id: id
            )

            return self.F.process(action: action, context: context)
        }
        
        assertion(_state)

        return WorkInspection(work: work, tester: self)
    }

    func registerInspection(_ inspection: WorkInspection<F>) {
        inspectionList.insert(inspection)
    }

    func removeInspection(_ inspection: WorkInspection<F>) {
        guard let originalInspection = inspectionList.firstIndex(of: inspection) else {
            reportIssue("attempted to get inspection when there is no entry in teh inspectionlist")
            return
        }

        guard inspection.id == inspectionList[originalInspection].id else {
            reportIssue("attempted to remove an inspection with a different id")
            return
        }

        guard inspection.children.isEmpty else {
            reportIssue("removing inspection while children pending")
            return
        }

        guard inspection.subscriptions.isEmpty else {
            reportIssue("there are still subscriptions running, please indicate that the stream is finished")
            return
        }

        inspectionList.remove(inspection)
    }

    func removeInspection(_ inspectionID: AnyHashableSendable) {
        let inspection = inspectionList.first {
            $0.id == inspectionID
        }

        guard let inspection else {
            reportIssue("attempted to remove an inspection that does not exist")
            return
        }

        inspection.completion = .finished
        inspection.operationAssertionDone = true
        inspectionList.remove(inspection)
    }
}

extension Tester where State: Identifiable {
    public convenience init(
        state: State
    ) {
        self.init(
            state: state,
            id: Feature<F>.makeID(from: state.id)
        )
    }
}

// MARK: - WorkInspection

@MainActor
public final class WorkInspection<F: FeatureBlueprint>: Identifiable, @preconcurrency Hashable {
    public typealias Action = F.Action
    public typealias Dependency = F.Dependency

    enum Completion: Hashable, Sendable {
        case pending
        case finished
    }

    public let id: AnyHashableSendable

    fileprivate var children: [WorkInspection] = []
    fileprivate var completion: Completion = .pending
    fileprivate var subscriptions: [WorkInspection] = []
    fileprivate let work: Work<Action, Dependency>
    fileprivate var operationAssertionDone = false

    fileprivate weak var parent: WorkInspection?
    fileprivate weak var tester: Tester<F>?

    var isSubscriptionWork: Bool {
        guard case .run(let run) = work.operation else {
            return false
        }

        guard
            run.configuration.fireAndForget,
            run.testPlan?.isContinuous == true
        else { return false }

        return true
    }

    init(
        work: Work<Action, Dependency>,
        tester: Tester<F>,
        parent: WorkInspection? = nil
    ) {
        var identifier: AnyHashableSendable?
        if case .run(let run) = work.operation {
            if let cancellation = run.configuration.cancellationID {
                identifier = cancellation
            }
        }

        self.id = identifier ?? AnyHashableSendable(value: UUID())
        self.work = work
        self.tester = tester
        self.parent = parent

        tester.registerInspection(self)
    }

    deinit {
        if completion == .pending {
            reportIssue("de initializing inspection while there's work pending")
        }

        if !children.isEmpty {
            reportIssue("de initializing inspection that still has children")
        }

        if !operationAssertionDone {
            reportIssue("initial operation assertion has not been called please call the assert functions provided by WorkInspection class")
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: WorkInspection, rhs: WorkInspection) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Assertions

extension WorkInspection {
    public func assertDone() {
        guard case .done = work.operation else {
            reportIssue("Expected the Work to be \(work.operation) but received .done assertion")
            return
        }

        guard children.isEmpty else {
            reportIssue("children of the current work \(id) expected to be empty but it is not")
            return
        }

        self.completion = .finished
        self.operationAssertionDone = true
        tester?.removeInspection(self)
        return
    }

    public func assertCancel(_ id: some (Hashable & Sendable)) {
        guard case .cancel(let cancelID) = work.operation else {
            reportIssue("asserted for cancellation but the actual operation is \(work.operation)")
            return
        }

        guard cancelID == AnyHashableSendable(value: id) else {
            reportIssue("id: \(id) is not equal to cancellationID: \(cancelID)")
            return
        }

        self.completion = .finished
        self.operationAssertionDone = true
        tester?.removeInspection(cancelID)
        tester?.removeInspection(self)
    }

    @discardableResult
    public func assertRun(
        _ configuration: (Work<Action, Dependency>.RunConfiguration) -> Void = { _ in  }
    ) -> Self {
        guard case .run(let run) = work.operation else {
            reportIssue("expected the operation to be .run but received \(work.operation)")
            return self
        }

        self.operationAssertionDone = true
        configuration(run.configuration)
        return self
    }
    
    public func assertMerge(_ numberOfWorks: Int, swaps: (Int, Int)...) -> Self {
        guard case .merge(let works) = work.operation else {
            reportIssue("asserted .merge but the actual operation is \(work.operation)")
            return self
        }
        
        guard works.count == numberOfWorks else {
            withIssueReporters([.default, .breakpoint]) {
                reportIssue("expected number of works do not match")
            }
            
            return self
        }
        
        var swappedWorks = works
        
        for swap in swaps {
            guard swap.0 >= 0 && swap.1 >= 0 else {
                reportIssue("swap indices must be non-negative")
                return self
            }

            guard swap.0 < numberOfWorks && swap.1 < numberOfWorks else {
                reportIssue("swap indices are higher than the maximum number of works")
                return self
            }
            
            swappedWorks.swapAt(swap.0, swap.1)
        }
        
        self.children = swappedWorks.map {
            WorkInspection(work: $0, tester: tester!, parent: self)
        }

        self.operationAssertionDone = true
        return self
    }

    @discardableResult
    public func assertConcatenate(_ numberOfWorks: Int) -> Self {
        guard case .concatenate(let works) = work.operation else {
            reportIssue("expected \(work.operation) but asserted .concatenate")
            return self
        }

        guard works.count == numberOfWorks else {
            reportIssue("number of works: \(works.count) do not match to the asserted amount \(numberOfWorks)")
            return self
        }

        self.children = works.map {
            WorkInspection(work: $0, tester: tester!, parent: self)
        }

        self.operationAssertionDone = true
        return self
    }

    @inline(__always)
    public func forget() {
        for child in children {
            child.forget()
        }

        for subscription in self.subscriptions {
            subscription.forget()
        }

        self.children.removeAll()
        self.subscriptions.removeAll()
        tester?.removeInspection(self.id)
    }
}

// MARK: - feed

extension WorkInspection {
    private func handleFeedForTask<Value>(
        _ result: Result<Value, Error>,
        _ plan: Work<Action, Dependency>.TestPlan
    ) throws -> Action {
        guard plan.expectedInputType == Result<Value, Error>.self else {
            throw Tester<F>.Failure.message("mismatching expectation for \(Value.self)")
        }

        let outputs = plan.feed(.taskResult(result))

        guard let output = outputs.first else {
            throw Tester<F>.Failure.message("did not receive an output")
        }

        if let parent = parent {
            guard parent.children.first?.id == self.id else {
                throw Tester<F>.Failure.message("unexpected child completed out of order")
            }
            self.completion = .finished
            parent.childDone(self)
            tester?.removeInspection(self)
            return output
        }

        self.completion = .finished
        tester?.removeInspection(self)
        return output
    }

    private func handleFeedForStream<Value>(
        _ result: Result<Value, Error>,
        _ plan: Work<Action, Dependency>.TestPlan
    ) throws -> Action {
        guard plan.expectedInputType == Value.self else {
            throw Failure.message("Unexpected value type is sent")
        }

        let actions = switch result {
        case .success(let value):
            plan.feed(.streamValues([value]))
        case .failure(let error):
            plan.feed(.streamFailure(error))
        }

        return actions.first!
    }

    public func finishStream() {
        self.completion = .finished
        parent?.childFinishStream(self)
        tester?.removeInspection(self)
    }

    func feedResult<Value>(
        _ result: Result<Value, Error>
    ) throws -> Action {
        guard case .run(let run) = work.operation else {
            throw Failure.message("expected the operation to be .run but received \(work.operation)")
        }

        guard let plan = run.testPlan else {
            tester?.removeInspection(self.id)
            throw Tester<F>.Failure.message("there is no test plan for this")
        }

        return switch plan.kind {
        case .task:
            try handleFeedForTask(result, plan)
        case .stream:
            try handleFeedForStream(result, plan)
        }
    }

    func childFinishStream(_ child: WorkInspection) {
        guard let childIndex = self.subscriptions.firstIndex(of: child) else {
            reportIssue("unexpected child completed out of order")
            return
        }

        subscriptions[childIndex].completion = .finished
        subscriptions.remove(at: childIndex)

        if self.children.isEmpty && self.subscriptions.isEmpty {
            self.completion = .finished
            self.parent?.childDone(self)
            tester?.removeInspection(self)
        }
    }

    func childDone(_ child: WorkInspection<F>) {
        guard child.id == self.children.first?.id else {
            reportIssue("unexpected child completed out of order")
            return
        }

        guard self.children[0].completion == .finished else {
            reportIssue("the child has not completed its operation yet")
            return
        }

        self.children.remove(at: 0)

        if self.children.isEmpty && self.subscriptions.isEmpty {
            self.completion = .finished
            self.parent?.childDone(self)
            tester?.removeInspection(self)
        }
    }
}

// MARK: - Sub Inspections

extension WorkInspection {
    public func subInspection() throws -> WorkInspection {
        guard self.children.count == 1 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(1). please use other API")
        }

        let inspection = children[0]

        if inspection.isSubscriptionWork {
            self.subscriptions.append(inspection)
            self.children.removeFirst()
        }

        return inspection
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection) {
        guard self.children.count == 2 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(2). please use other API")
        }

        let inspection1 = children[0]
        let inspection2 = children[1]

        moveSubscriptionInspection(inspection1)
        moveSubscriptionInspection(inspection2)

        return (inspection1, inspection2)
    }

    private func moveSubscriptionInspection(_ inspection: WorkInspection) {
        if inspection.isSubscriptionWork {
            children.removeAll { $0 == inspection }
            subscriptions.append(inspection)
        }
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection, WorkInspection) {
        guard self.children.count == 3 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(3). please use other API")
        }

        let inspection1 = children[0]
        let inspection2 = children[1]
        let inspection3 = children[2]

        moveSubscriptionInspection(inspection1)
        moveSubscriptionInspection(inspection2)
        moveSubscriptionInspection(inspection3)

        return (inspection1, inspection2, inspection3)
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection, WorkInspection, WorkInspection) {
        guard self.children.count == 4 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(4). please use other API")
        }

        let inspection1 = children[0]
        let inspection2 = children[1]
        let inspection3 = children[2]
        let inspection4 = children[3]

        moveSubscriptionInspection(inspection1)
        moveSubscriptionInspection(inspection2)
        moveSubscriptionInspection(inspection3)
        moveSubscriptionInspection(inspection4)

        return (inspection1, inspection2, inspection3, inspection4)
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection, WorkInspection, WorkInspection, WorkInspection) {
        guard self.children.count == 5 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(5). please use other API")
        }

        let inspection1 = children[0]
        let inspection2 = children[1]
        let inspection3 = children[2]
        let inspection4 = children[3]
        let inspection5 = children[4]

        moveSubscriptionInspection(inspection1)
        moveSubscriptionInspection(inspection2)
        moveSubscriptionInspection(inspection3)
        moveSubscriptionInspection(inspection4)
        moveSubscriptionInspection(inspection5)

        return (inspection1, inspection2, inspection3, inspection4, inspection5)
    }
}

// MARK: - WorkInspection + Error

extension WorkInspection {
    enum Failure: Error, CustomStringConvertible {
        case message(String)

        var description: String {
            switch self {
            case .message(let msg):
                return msg
            }
        }
    }
}
