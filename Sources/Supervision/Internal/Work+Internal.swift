//
//  Work+TestPlan.swift
//  Supervision
//
//  Created by John Demirci on 1/15/26.
//

import Foundation

// MARK: - Test Plan

extension Work {
    struct TestPlan: @unchecked Sendable {
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
        let feed: @Sendable (TestInput) -> [Output]
    }
}

// MARK: - Execution Context

extension Work {
    struct ExecutionContext: Hashable, Sendable {
        let id: UUID
        let execution: @Sendable (Environment, @escaping @Sendable (Output) async -> Void) async -> Void

        init(
            execution: @Sendable @escaping (Environment, @Sendable @escaping (Output) async -> Void) async -> Void
        ) {
            self.id = UUID()
            self.execution = execution
        }

        func callAsFunction(
            _ environment: Environment,
            _ completion: @escaping @Sendable (Output) async -> Void
        ) async {
            await execution(environment, completion)
        }

        static func == (lhs: Work<Output, Environment>.ExecutionContext, rhs: Work<Output, Environment>.ExecutionContext) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}

// MARK: - Work.RunConfiguration Extensions

extension Work.RunConfiguration {
    func with(
        name: String?? = nil,
        cancellationID: AnyHashableSendable?? = nil,
        cancelInFlight: Bool? = nil,
        fireAndForget: Bool? = nil,
        debounce: Duration?? = nil,
        throttle: Duration?? = nil,
        priority: TaskPriority?? = nil
    ) -> Self {
        Self(
            name: name ?? self.name,
            cancellationID: cancellationID ?? self.cancellationID,
            cancelInFlight: cancelInFlight ?? self.cancelInFlight,
            fireAndForget: fireAndForget ?? self.fireAndForget,
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
