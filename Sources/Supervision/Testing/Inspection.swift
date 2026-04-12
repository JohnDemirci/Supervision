//
//  Inspection.swift
//  Supervision
//
//  Created by John Demirci on 4/10/26.
//

import Foundation

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

extension Inspection {
    @discardableResult
    public func assertDone(
        file: StaticString = #file,
        line: UInt = #line
    ) -> DoneInspection<Action, Environment> {
        let inspection = assertConcrete(
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
    ) -> CancelInspection<Action, Environment> {
        let inspection = assertConcrete(
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
    ) -> RunInspection<Action, Environment> {
        let inspection = assertConcrete(
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
    ) -> MergeInspection<Action, Environment> {
        assertConcrete(
            scope: .merge,
            file: file,
            line: line
        )
    }

    public func assertConcatenate(
        file: StaticString = #file,
        line: UInt = #line
    ) -> ConcatenateInspection<Action, Environment> {
        assertConcrete(
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
    ) -> T where T.Action == Action, T.Environment == Environment {
        precondition(
            scope == expectedScope,
            "Expected inspection scope \(expectedScope), got \(scope).",
            file: file,
            line: line
        )

        guard let typedInspection = self as? T else {
            preconditionFailure(
                "Expected inspection type \(inspectionType), got \(Swift.type(of: self)).",
                file: file,
                line: line
            )
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
