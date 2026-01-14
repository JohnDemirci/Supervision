//
//  Work.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

import Foundation

enum TestInput: @unchecked Sendable {
    case taskResult(Any)              // expects Result<T, Error> boxed as Any
    case streamValues([Any])          // expects [Element] boxed as Any
    case streamFailure(Error)
    case streamFinished
}

extension TaskPriority: @retroactive Hashable {}

public struct Work<Output, Environment>: Sendable {
    public indirect enum Operation: Sendable {
        case done
        case cancel(AnyHashableSendable)
        case run(Run)
        case merge(Array<Work<Output, Environment>>)
        case concatenate(Array<Work<Output, Environment>>)
    }


    public struct RunConfiguration: Sendable, Hashable {
        public let name: String?
        public let cancellationID: AnyHashableSendable?
        public let cancelInFlight: Bool
        public let debounce: Duration?
        public let throttle: Duration?
        public let priority: TaskPriority?
        public let fireAndForget: Bool

        public init(
            name: String? = nil,
            cancellationID: AnyHashableSendable? = nil,
            cancelInFlight: Bool = false,
            fireAndForget: Bool = false,
            debounce: Duration? = nil,
            throttle: Duration? = nil,
            priority: TaskPriority? = nil
        ) {
            self.name = name
            self.cancellationID = cancellationID
            self.cancelInFlight = cancelInFlight
            self.debounce = debounce
            self.throttle = throttle
            self.priority = priority
            self.fireAndForget = fireAndForget
        }

        func with(
            name: String?? = nil,
            cancellationID: AnyHashableSendable?? = nil,
            cancelInFlight: Bool? = nil,
            fireAndForget: Bool? = nil,
            debounce: Duration?? = nil,
            throttle: Duration?? = nil,
            priority: TaskPriority?? = nil
        ) -> RunConfiguration {
            RunConfiguration(
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

    public struct Run: Sendable {
        let configuration: RunConfiguration
        let execute: @Sendable (Environment, @escaping @Sendable (Output) async -> Void) async -> Void
        let testPlan: TestPlan?

        init(
            configuration: RunConfiguration = .init(),
            execute: @Sendable @escaping (Environment, @Sendable @escaping (Output) async -> Void) async -> Void,
            testPlan: TestPlan? = nil
        ) {
            self.configuration = configuration
            self.execute = execute
            self.testPlan = testPlan
        }

        func with(configuration: RunConfiguration) -> Run {
            Run(
                configuration: configuration,
                execute: execute,
                testPlan: testPlan
            )
        }
    }

    struct TestPlan: @unchecked Sendable {
        enum Kind: Sendable, RawRepresentable {
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

            typealias RawValue = String

            case task
            case stream
        }

        let kind: Kind
        let expectedInputType: Any.Type
        let isContinuous: Bool
        let feed: @Sendable (TestInput) -> [Output]
    }

    public let operation: Operation

    init(operation: Operation) {
        self.operation = operation
    }
}

extension Work {
    public static var done: Self {
        Work(operation: .done)
    }

    public static func cancel(_ id: some (Sendable & Hashable)) -> Self {
        Work(operation: .cancel(AnyHashableSendable(value: id)))
    }

    public static func run<Value>(
        config: RunConfiguration = .init(),
        body: @escaping @Sendable (Environment) async throws -> Value,
        map: @escaping @Sendable (Result<Value, Error>) -> Output
    ) -> Self {
        Work(
            operation: .run(
                Run(
                    configuration: config,
                    execute: { env, send in
                        do { await send(map(.success(try await body(env)))) }
                        catch is CancellationError { return }
                        catch { await send(map(.failure(error))) }
                    },
                    testPlan: isTesting() ? TestPlan(
                        kind: .task,
                        expectedInputType: Result<Value, Error>.self,
                        isContinuous: false,
                        feed: { input in
                            guard
                                case let .taskResult(any) = input,
                                let typed = any as? Result<Value, Error>
                            else { return [] }

                            return [map(typed)]
                        }
                    ) : nil
                )
            )
        )
    }

    public static func subscribe<Value: Sendable>(
        config: RunConfiguration = .init(fireAndForget: true),
        stream: @escaping @Sendable (Environment) async throws -> AsyncThrowingStream<Value, Error>,
        map: @escaping @Sendable (Result<Value, Error>) -> Output
    ) -> Self {
        Work(
            operation: .run(
                Run(
                    configuration: config,
                    execute: { env, send in
                        do {
                            let sequence = try await stream(env)
                            for try await value in sequence {
                                await send(map(.success(value)))
                            }
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(map(.failure(error)))
                        }
                    },
                    testPlan: isTesting() ? TestPlan(
                        kind: .stream,
                        expectedInputType: Value.self,
                        isContinuous: true,
                        feed: { input in
                            switch input {
                            case let .streamValues(values):
                                return values.compactMap { $0 as? Value }.map { map(.success($0)) }
                            case let .streamFailure(error):
                                return [map(.failure(error))]
                            case .streamFinished, .taskResult:
                                return []
                            }
                        }
                    ) : nil
                )
            )
        )
    }

    public static func fireAndForget(
        config: RunConfiguration = .init(fireAndForget: true),
        body: @escaping @Sendable (Environment) async throws -> Void
    ) -> Self {
        Work(
            operation: .run(
                Run(
                    configuration: config,
                    execute: { env, _ in
                        do { try await body(env) }
                        catch { return }
                    },
                    testPlan: nil
                )
            )
        )
    }

    public static func merge(_ works: Work<Output, Environment>...) -> Self {
        merge(works)
    }

    public static func merge(_ works: [Work<Output, Environment>]) -> Self {
        let nonEmptyWorks = works.filter {
            if case .done = $0.operation { return false }
            return true
        }

        if nonEmptyWorks.isEmpty { return .done }
        if nonEmptyWorks.count == 1 { return nonEmptyWorks.first! }

        return Work(operation: .merge(nonEmptyWorks))
    }

    public static func concatenate(_ works: Work<Output, Environment>...) -> Self {
        concatenate(works)
    }

    public static func concatenate(_ works: [Work<Output, Environment>]) -> Self {
        let nonEmptyWorks = works.filter {
            if case .done = $0.operation { return false }
            return true
        }

        if nonEmptyWorks.isEmpty { return .done }
        if nonEmptyWorks.count == 1 { return nonEmptyWorks.first! }

        return Work(operation: .concatenate(nonEmptyWorks))
    }
}

extension Work {
    public func named(_ name: String) -> Self {
        modifyRun { run in
            run.with(configuration: run.configuration.with(name: name))
        }
    }

    public func cancellable(
        id: some (Sendable & Hashable),
        cancelInFlight: Bool = false
    ) -> Self {
        modifyRun { run in
            run.with(
                configuration: run.configuration.with(
                    cancellationID: AnyHashableSendable(value: id),
                    cancelInFlight: cancelInFlight
                )
            )
        }
    }

    public func priority(_ priority: TaskPriority) -> Self {
        modifyRun { run in
            run.with(configuration: run.configuration.with(priority: priority))
        }
    }

    public func throttle(for duration: Duration) -> Self {
        modifyRun { run in
            assert(run.configuration.cancellationID != nil, "throttle is only valid for cancellable works")
            return run.with(configuration: run.configuration.with(throttle: duration))
        }
    }

    public func debounce(for duration: Duration) -> Self {
        modifyRun { run in
            run.with(configuration: run.configuration.with(debounce: duration))
        }
    }

    private func modifyRun(_ transform: (Run) -> Run) -> Self {
        return switch operation {
        case .run(let run):
            Work(operation: .run(transform(run)))

        case .merge(let works):
            Work(operation: .merge(works.map { $0.modifyRun(transform) }))

        case .concatenate(let works):
            Work(operation: .concatenate(works.map { $0.modifyRun(transform) }))

        case .done, .cancel:
            self
        }
    }

    func map<NewOutput>(
        _ transform: @escaping @Sendable (Output) -> NewOutput
    ) -> Work<NewOutput, Environment> {
        switch operation {
        case .done:
            return .done
        case .cancel(let id):
            return .cancel(id)
        case .merge(let works):
            return Work<NewOutput, Environment>.merge(
                Work.map(from: works, transform: transform)
            )
        case .concatenate(let works):
            return Work<NewOutput, Environment>.concatenate(
                Work.map(from: works, transform: transform)
            )
        case .run(let run):
            return Work<NewOutput, Environment>(
                operation: .run(
                    Run.map(from: run, transform: transform)
                )
            )
        }
    }
}

extension Work where Output: Sendable {
    public static func send(_ output: Output) -> Self {
        Work(
            operation: .run(
                Run(
                    configuration: .init(),
                    execute: { _, send in
                        await send(output)
                    },
                    testPlan: TestPlan(
                        kind: .task,
                        expectedInputType: Void.self,
                        isContinuous: false,
                        feed: { _ in [output] }
                    )
                )
            )
        )
    }
}

private extension Work {
    static func map<OldOutput, NewOutput>(
        from olderWorks: [Work<OldOutput, Environment>],
        transform: @Sendable @escaping (OldOutput) -> NewOutput
    ) -> [Work<NewOutput, Environment>] {
        olderWorks.map { olderWork in
            olderWork.map { olderOutput in
                transform(olderOutput)
            }
        }
    }
}

private extension Work.Run {
    static func map<OldOutput, NewOutput>(
        from run: Work<OldOutput, Environment>.Run,
        transform: @Sendable @escaping (OldOutput) -> NewOutput
    ) -> Work<NewOutput, Environment>.Run {
        Work<NewOutput,Environment>.Run(
            configuration: Work<NewOutput,
            Environment>.RunConfiguration(
                name: run.configuration.name,
                cancellationID: run.configuration.cancellationID,
                cancelInFlight: run.configuration.cancelInFlight,
                debounce: run.configuration.debounce,
                throttle: run.configuration.throttle,
                priority: run.configuration.priority
            ),
            execute: { env, send in
                await run.execute(env) { output in
                    await send(transform(output))
                }
            },
            testPlan: run.testPlan.map { currentPlan in
                Work<NewOutput, Environment>.TestPlan(
                    kind: Work<NewOutput, Environment>.TestPlan.Kind(rawValue: currentPlan.kind.rawValue)!,
                    expectedInputType: currentPlan.expectedInputType,
                    isContinuous: currentPlan.isContinuous,
                    feed: { input in
                        currentPlan.feed(input).map(transform)
                    }
                )
            }
        )
    }
}
