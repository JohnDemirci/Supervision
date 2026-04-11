//
//  Work+TestPlan.swift
//  Supervision
//
//  Created by John Demirci on 1/15/26.
//

import Foundation

// MARK: - Test Plan

struct TestPlan<Action>: @unchecked Sendable {
    enum Kind: Hashable, Sendable, RawRepresentable {
        case task
        case stream

        typealias RawValue = String

        init?(rawValue: String) {
            if rawValue == "task" {
                self = .task
            } else if rawValue == "stream" {
                self = .stream
            } else {
                return nil
            }
        }

        var rawValue: String {
            switch self {
            case .task: "task"
            case .stream: "stream"
            }
        }
    }

    let kind: Kind
    let expectedInputType: Any.Type
    let isContinuous: Bool
    let feed: @Sendable (TestInput) -> [Action]
}

// MARK: - Execution Context

struct ExecutionContext<Action, Dependency>: Hashable, Sendable {
    let id: UUID
    let execution: @Sendable (Dependency, @escaping @Sendable (Action) async -> Void) async -> Void

    init(
        execution: @Sendable @escaping (Dependency, @Sendable @escaping (Action) async -> Void) async -> Void
    ) {
        self.id = UUID()
        self.execution = execution
    }

    static func == (
        lhs: ExecutionContext<Action, Dependency>,
        rhs: ExecutionContext<Action, Dependency>
    ) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Work.RunConfiguration Extensions

extension Work.RunConfiguration {
    func with(
        name: String?? = nil,
        cancellationID: AnyHashableSendable?? = nil,
        cancelInFlight: Bool? = nil,
        fireAndForget: Bool? = nil,
        isSubscription: Bool? = nil,
        debounce: Duration?? = nil,
        throttle: Duration?? = nil,
        priority: TaskPriority?? = nil
    ) -> Self {
        Self(
            name: name ?? self.name,
            cancellationID: cancellationID ?? self.cancellationID,
            cancelInFlight: cancelInFlight ?? self.cancelInFlight,
            fireAndForget: fireAndForget ?? self.fireAndForget,
            isSubscription: isSubscription ?? self.isSubscription,
            debounce: debounce ?? self.debounce,
            throttle: throttle ?? self.throttle,
            priority: priority ?? self.priority
        )
    }
}

enum TestInput: @unchecked Sendable {
    case taskResult(Any)              // expects Result<T, Error> boxed as Any
    case streamValues([Any])          // expects [Element] boxed as Any
    case streamFailure(Error)
    case streamFinished
}
