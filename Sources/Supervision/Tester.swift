//
//  Tester.swift
//  Supervision
//
//  Created by John Demirci on 1/9/26.
//

import Foundation
import OSLog
import IssueReporting

@dynamicMemberLookup
public final class Tester<Feature: FeatureProtocol> {
    enum Failure: Error, CustomStringConvertible {
        case message(String)

        var description: String {
            switch self {
            case .message(let message):
                return message
            }
        }
    }

    public typealias Action = Feature.Action
    public typealias Dependency = Feature.Dependency
    public typealias State = Feature.State

    let feature: Feature
    private var _state: State

    private var inspectionList: [WorkInspection<Feature>] = []

    deinit {
        if !inspectionList.isEmpty {
            reportIssue("pending inspections: \(inspectionList)")
        }
    }

    public init(state: State) {
        self.feature = .init()
        self._state = state
    }

    public subscript<Subject>(
        dynamicMember keyPath: KeyPath<State, Subject>
    ) -> Subject {
        return _state[keyPath: keyPath]
    }

    public func feedResult<Value>(
        for inspection: WorkInspection<Feature>,
        result: Result<Value, Error>,
        assertion: (State) -> Void
    ) throws -> WorkInspection<Feature> {
        inspection.assertRun()
        let action = try inspection.feedResult(result)
        return send(action, assertion: assertion)
    }

    public func send(
        _ action: Action,
        assertion: (State) -> Void = { _ in }
    ) -> WorkInspection<Feature> {
        let work: Feature.FeatureWork = withUnsafeMutablePointer(
            to: &_state
        ) { [self] pointer in
            let context = Context<Feature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer)
            )

            return self.feature.process(action: action, context: context)
        }
        
        assertion(_state)

        return WorkInspection(work: work, tester: self)
    }

    func registerInspection(_ inspection: WorkInspection<Feature>) {
        inspectionList.append(inspection)
    }

    func removeInspection(_ inspection: WorkInspection<Feature>) {
        guard let originalInspectionIndex = inspectionList.firstIndex(where: { $0.id == inspection.id }) else {
            reportIssue("attempted to get inspection when there is no entry in teh inspectionlist")
            return
        }

        guard inspection.id == inspectionList[originalInspectionIndex].id else {
            reportIssue("attempted to remove an inspection with a different id")
            return
        }

        guard inspection.children.isEmpty else {
            reportIssue("removing inspection while children pending")
            return
        }

        inspectionList.remove(at: originalInspectionIndex)
    }

    func removeInspection(_ inspectionID: AnyHashableSendable) {
        var indexList: [Int] = []
        for (index, value) in inspectionList.enumerated() {
            if value.id == inspectionID {
                indexList.append(index)
            }
        }

        indexList.forEach {
            inspectionList[$0].completion = .finished
            inspectionList.remove(at: $0)
        }
    }
}

// MARK: - WorkInspection

public final class WorkInspection<Feature: FeatureProtocol>: Identifiable {
    public typealias Action = Feature.Action
    public typealias Dependency = Feature.Dependency

    enum Completion: Hashable, Sendable {
        case pending
        case finished
    }

    public let id: AnyHashableSendable

    fileprivate var children: [WorkInspection] = []
    fileprivate var completion: Completion = .pending
    fileprivate let work: Work<Action, Dependency>

    fileprivate weak var parent: WorkInspection?
    fileprivate weak var tester: Tester<Feature>?

    init(
        work: Work<Action, Dependency>,
        tester: Tester<Feature>,
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
            guard swap.0 < numberOfWorks && swap.1 < numberOfWorks else {
                reportIssue("swap indices are higher than the maximum number of works")
                return self
            }
            
            swappedWorks.swapAt(swap.0, swap.1)
        }
        
        self.children = swappedWorks.map {
            WorkInspection(work: $0, tester: tester!, parent: self)
        }
        
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

        return self
    }

    @inline(__always)
    public func forget() {
        for child in children {
            child.forget()
        }

        self.children.removeAll()
        tester?.removeInspection(self.id)
    }
}

// MARK: - feed

extension WorkInspection {
    func feedResult<Value>(
        _ result: Result<Value, Error>
    ) throws -> Action {
        guard case .run(let run) = work.operation else {
            throw Tester<Feature>.Failure.message("expected the operation to be .run but received \(work.operation)")
        }

        guard let plan = run.testPlan else {
            tester?.removeInspection(self.id)
            throw Tester<Feature>.Failure.message("there is no test plan for this")
        }

        guard plan.kind == .task else {
            throw Tester<Feature>.Failure.message("expected a task type")
        }

        guard plan.expectedInputType == Result<Value, Error>.self else {
            throw Tester<Feature>.Failure.message("mismatching expectation for \(Value.self)")
        }

        let outputs = plan.feed(.taskResult(result))

        guard let output = outputs.first else {
            throw Tester<Feature>.Failure.message("did not receive an output")
        }

        if let parent = parent {
            guard parent.children.first?.id == self.id else {
                throw Tester<Feature>.Failure.message("unexpected child completed out of order")
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

    func childDone(_ child: WorkInspection<Feature>) {
        guard child.id == self.children.first?.id else {
            reportIssue("unexpected child completed out of order")
            return
        }

        guard self.children[0].completion == .finished else {
            reportIssue("the child has not completed its operation yet")
            return
        }

        self.children.remove(at: 0)

        if self.children.isEmpty {
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

        return children[0]
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection) {
        guard self.children.count == 2 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(2). please use other API")
        }

        return (children[0], children[1])
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection, WorkInspection) {
        guard self.children.count == 3 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(3). please use other API")
        }

        return (children[0], children[1], children[2])
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection, WorkInspection, WorkInspection) {
        guard self.children.count == 4 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(4). please use other API")
        }

        return (children[0], children[1], children[2], children[3])
    }

    public func subInspections() throws -> (WorkInspection, WorkInspection, WorkInspection, WorkInspection, WorkInspection) {
        guard self.children.count == 5 else {
            throw Failure.message("the count of the children \(children.count) does not match the API offers \(5). please use other API")
        }

        return (children[0], children[1], children[2], children[3], children[4])
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
