//
//  Inspection.swift
//  Supervision
//
//  Created by John Demirci on 4/10/26.
//

import Foundation
import IssueReporting

public protocol Inspection<Action, Environment>: AnyObject, Identifiable {
    typealias InspectedWork = Work<Action, Environment>

    associatedtype Action
    associatedtype Environment

    var work: InspectedWork { get }
    var scope: InspectionScope { get }
    var id: AnyHashableSendable { get }
}

protocol _Inspection<Action, Environment>: Inspection {
    associatedtype Event = Void

    var toBeForgotten: Bool  { get set }
    var sendEvent: (Event) -> Void { get }
}

extension _Inspection where Event == Void {
    var sendEvent: (Event) -> Void {
        { _ in }
    }
}

extension _Inspection {
    var toBeForgotten: Bool {
        get { false }
        set {  }
    }
}

public enum InspectionFailure: Error {
    case scopeMismatch
    case castingFailed
}

extension Inspection {
    @discardableResult
    public func assertDone(
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> DoneInspection<Action, Environment> {
        let inspection = try assertConcrete(
            scope: .done,
            as: DoneInspection<Action, Environment>.self,
            file: file,
            line: line
        )

        inspection.complete()

        return inspection
    }

    public func assertCancel(
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> CancelInspection<Action, Environment> {
        let inspection = try assertConcrete(
            scope: .cancel,
            as: CancelInspection<Action, Environment>.self,
            file: file,
            line: line
        )

        inspection.startCancellation()

        return inspection
    }

    public func assertRun(
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> RunInspection<Action, Environment> {
        let inspection = try assertConcrete(
            scope: .run,
            as: RunInspection<Action, Environment>.self,
            file: file,
            line: line
        )

        if !inspection.isSubscription {
            if inspection.config.fireAndForget {
                inspection.toBeForgotten = true
            }
        }

        return inspection
    }

    public func assertMerge(
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> MergeInspection<Action, Environment> {
        try assertConcrete(
            scope: .merge,
            file: file,
            line: line
        )
    }

    public func assertConcatenate(
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> ConcatenateInspection<Action, Environment> {
        try assertConcrete(
            scope: .concatenate,
            file: file,
            line: line
        )
    }

    private func assertConcrete<T: Inspection>(
        scope expectedScope: InspectionScope,
        as inspectionType: T.Type = T.self,
        file: StaticString,
        line: UInt
    ) throws -> T where T.Action == Action, T.Environment == Environment {
        guard scope == expectedScope else {
            reportIssue(InspectionFailure.scopeMismatch)
            throw InspectionFailure.scopeMismatch
        }

        guard let typedInspection = self as? T else {
            reportIssue(InspectionFailure.castingFailed)
            throw InspectionFailure.castingFailed
        }

        return typedInspection
    }
}

extension Inspection {
    public func forget() {
        let current = self as! (any _Inspection<Action, Environment>)
        current.toBeForgotten = true
    }
}

enum InspectionStatus {
    case pending
    case finished
}

public enum InspectionScope {
    case done
    case cancel
    case run
    case merge
    case concatenate
    case subscription
}
