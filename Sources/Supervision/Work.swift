//
//  Work.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

import Foundation

public struct Work<Output, Environment>: Sendable, Hashable {
    public enum Operation: Sendable, Hashable {
        case done
        case cancel(AnyHashableSendable)
        case run(Run)
        indirect case merge(Array<Work<Output, Environment>>)
        indirect case concatenate(Array<Work<Output, Environment>>)
    }

    /// Configuration for the Work
    public struct RunConfiguration: Sendable, Hashable {
        /// The name of the task to be executed.
        public let name: String?
        
        /// Identifier for the Work that can be cancelled
        public let cancellationID: AnyHashableSendable?
        
        /// Indicator if the old work already in flight should be cancelled in favor of the new work.
        public let cancelInFlight: Bool
        
        /// Duration to wait before executing a task.
        public let debounce: Duration?
        
        /// Duration to wait before executing another task.
        ///
        /// - Important: You must provide a cancellation ID.
        public let throttle: Duration?
        
        /// Specification of the task priority.
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
    }

    /// A Work operation that represents an outside work to be performed.
    public struct Run: Hashable, Sendable {
        let configuration: RunConfiguration
        let execute: ExecutionContext
        let testPlan: TestPlan?

        init(
            configuration: RunConfiguration = .init(),
            execute: ExecutionContext,
            testPlan: TestPlan? = nil
        ) {
            self.configuration = configuration
            self.execute = execute
            self.testPlan = testPlan
        }

        public static func == (
            lhs: Work<Output, Environment>.Run,
            rhs: Work<Output, Environment>.Run
        ) -> Bool {
            lhs.configuration == rhs.configuration &&
            lhs.execute == rhs.execute
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(execute)
            hasher.combine(configuration)
        }

        func with(configuration: Work<Output, Environment>.RunConfiguration) -> Self {
            Self(
                configuration: configuration,
                execute: execute,
                testPlan: testPlan
            )
        }
    }

    public let operation: Operation

    init(operation: Operation) {
        self.operation = operation
    }
}



// MARK: - Work Instantiation

extension Work {
    /// No work to be done.
    public static var done: Self {
        Work(operation: .done)
    }

    /// A work meant to cancel an existing Work.
    ///
    /// - Parameters:
    ///    - id: A value that conforms to the `Hashable` & `Sendable` protocols.
    ///
    /// - Returns: A Work that's operation is to cancel another work.
    public static func cancel(_ id: some (Sendable & Hashable)) -> Self {
        Work(operation: .cancel(AnyHashableSendable(value: id)))
    }

    /// Represents an async work to be performed
    ///
    /// - Parameters:
    ///    - config: The configuration for the Work.
    ///    - body:  A closure to perform the work. It takes and `Environment` and returns a generic `Value`
    ///    - map: A closure that takes a `Result` for the operation and maps into Output
    ///
    /// - Returns: Work with a task to perfom the specified task.
    public static func run<Value>(
        config: RunConfiguration = .init(),
        body: @escaping @Sendable (Environment) async throws -> Value,
        map: @escaping @Sendable (Result<Value, Error>) -> Output
    ) -> Self {
        Work(
            operation: .run(
                Run(
                    configuration: config,
                    execute: ExecutionContext { env, send in
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

    /// Work that's job is to subscribe to a stream and listen for the values.
    ///
    /// - Parameters:
    ///    - config: configuration for the Work's task.
    ///    - stream: The closure that returns the desired stream. The return value needs to conform to AsyncSequence
    ///    - map: A closure that takes the result and maps into an Output to be executed.
    ///
    /// - Returns: Work for subscription.
    public static func subscribe<Value: Sendable, S>(
        config: RunConfiguration = .init(fireAndForget: true),
        stream: @escaping @Sendable (Environment) async throws -> S,
        map: @escaping @Sendable (Result<Value, Error>) -> Output
    ) -> Self
    where
        S: AsyncSequence & Sendable,
        S.Element == Value
    {
        return Work(
            operation: .run(
                Run(
                    configuration: config.fireAndForget ? config : config.with(fireAndForget: true),
                    execute: ExecutionContext { env, send in
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

    /// Creates a work to perform a task and forget about it.
    ///
    /// - Parameters:
    ///    - config: The configuration for the Work.
    ///    - body:  A closure to perform the work. It takes and `Environment` and returns a generic `Value`
    ///
    /// - Returns: A fire and forget type of Work.
    public static func fireAndForget(
        config: RunConfiguration = .init(fireAndForget: true),
        body: @escaping @Sendable (Environment) async throws -> Void
    ) -> Self {
        Work(
            operation: .run(
                Run(
                    configuration: config.fireAndForget ? config : config.with(fireAndForget: true),
                    execute: ExecutionContext { env, _ in
                        do { try await body(env) }
                        catch { return }
                    },
                    testPlan: nil
                )
            )
        )
    }
    
    /// Runs multiple works concurrently and waits all of them the finish at the end.
    ///
    /// - Note: Works that fail or throw error do not effect the other works.
    ///
    /// - Parameters:
    ///    - works: A variadic list of ``Work<Output, Environment>``
    ///
    /// - Returns: A ``Work<Output, Environment>`` merged with the provided works.
    public static func merge(_ works: Work<Output, Environment>...) -> Self {
        merge(works)
    }

    /// Runs multiple works concurrently and waits all of them the finish at the end.
    ///
    /// - Note: Works that fail or throw error do not effect the other works.
    ///
    /// - Parameters:
    ///    - works: An array of ``Work<Output, Environment>``
    ///
    /// - Returns: A ``Work<Output, Environment>`` merged with the provided works.
    public static func merge(_ works: [Work<Output, Environment>]) -> Self {
        let nonEmptyWorks = works.filter {
            if case .done = $0.operation { return false }
            return true
        }

        if nonEmptyWorks.isEmpty { return .done }
        if nonEmptyWorks.count == 1 { return nonEmptyWorks.first! }

        return Work(operation: .merge(nonEmptyWorks))
    }

    /// A Work type that runs multiple works sequentially.
    ///
    /// - Note: Upon failure, the remaining works will not be fired off.
    ///
    /// - Parameters:
    ///    - works: A variadic list of ``Work<Output, Environment>``
    ///
    /// - Returns: ``Work<Output, Environment>`` containing the provided works to be run sequentially.
    public static func concatenate(_ works: Work<Output, Environment>...) -> Self {
        concatenate(works)
    }

    /// A Work type that runs multiple works sequentially.
    ///
    /// - Note: Upon failure, the remaining works will not be fired off.
    ///
    /// - Parameters:
    ///    - works: An array of ``Work<Output, Environment>``
    ///
    /// - Returns: ``Work<Output, Environment>`` containing the provided works to be run sequentially.
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
    /// Attaches a name to the Work's task.
    ///
    /// - Parameters:
    ///    - name: The new name of the Work's task.
    ///
    /// - Returns: Work with a modified name for its Task.
    public func named(_ name: String) -> Self {
        modifyRun { run in
            run.with(configuration: run.configuration.with(name: name))
        }
    }

    /// Attaches an identifier to the work to be cancelled later when invoked.
    ///
    /// - Parameters:
    ///    - id: A value that conforms to the `Sendable` & `Hashable` protocols.
    ///    - cancelInFlight: boolean value to tell the system if there is a new work while there is an existing work in flight whether to cancel that work or not. if it is set to true the new work is prioritized, if it is false, the new work will be swallowen prioritizing the work in flight.
    public func cancellable(
        id: some (Sendable & Hashable),
        cancelInFlight: Bool = false
    ) -> Self {
        switch self.operation {
        case .merge, .concatenate:
            assertionFailure("cannot have a singular ID when merging or concatenating works")
            return self
        default:
            break
        }
        
        return modifyRun { run in
            run.with(
                configuration: run.configuration.with(
                    cancellationID: AnyHashableSendable(value: id),
                    cancelInFlight: cancelInFlight
                )
            )
        }
    }

    /// Updates the priortiy of the Task for the Work.
    ///
    /// - Note: This function only updates if the Work operation is ``Work.Operation.run``, ``Work.Operation.concatenate``, ``Work.Operation.merge``
    ///
    /// - Parameters:
    ///    - priority: The task priority.
    ///
    /// - Returns: A work with the updated priority.
    public func priority(_ priority: TaskPriority) -> Self {
        modifyRun { run in
            run.with(configuration: run.configuration.with(priority: priority))
        }
    }

    /// Adds throttle to the Work
    ///
    /// - Important: You must provide a an id using `cancellable` otherwise this function has not throttle effect.
    ///
    /// - Parameters:
    ///    - duration: The duration before making able to make another network request.
    ///
    /// - Returns: A throttled Work
    public func throttle(for duration: Duration) -> Self {
        modifyRun { run in
            assert(run.configuration.cancellationID != nil, "throttle is only valid for cancellable works")
            return run.with(configuration: run.configuration.with(throttle: duration))
        }
    }

    /// Debounces the execution of the work
    ///
    /// - Parameters:
    ///    - duration: time duration to debounce
    ///
    /// - Returns: A Work do be debounced before execution
    public func debounce(for duration: Duration) -> Self {
        modifyRun { run in
            run.with(configuration: run.configuration.with(debounce: duration))
        }
    }

    /// Transforms the current work with an Output to a new work with a new Output
    ///
    /// - Parameters:
    ///    - transform: Closure that takes output and returns a new output
    ///
    /// - Returns: A new Work<NewOutput, Environment>.
    public func map<NewOutput>(
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
    /// Creates a work for an `Output` to be immediately sent.
    ///
    /// - Parameters:
    ///    - output: Action to feed.
    ///
    /// - Returns: Work for the given output
    public static func send(_ output: Output) -> Self {
        Work(
            operation: .run(
                Run(
                    configuration: .init(),
                    execute: ExecutionContext { _, send in
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
    
    func modifyRun(_ transform: (Run) -> Run) -> Self {
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
            execute: Work<NewOutput, Environment>.ExecutionContext { env, send in
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

// MARK: - Work.Operation Hashable Conformance

extension Work.Operation {
    public static func == (lhs: Work<Output, Environment>.Operation, rhs: Work<Output, Environment>.Operation) -> Bool {
        switch (lhs, rhs) {
        case (.done, .done):
            return true
        case let (.cancel(l), .cancel(r)):
            return l == r
        case let (.run(l), .run(r)):
            return l == r
        case let (.merge(l), .merge(r)):
            return l == r
        case let (.concatenate(l), .concatenate(r)):
            return l == r
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .done:
            hasher.combine(0)
            hasher.combine("done")
        case .cancel(let id):
            hasher.combine(1)
            hasher.combine(id)
        case .run(let run):
            hasher.combine(2)
            hasher.combine(run)
        case .merge(let works):
            hasher.combine(3)
            hasher.combine(works)
        case .concatenate(let works):
            hasher.combine(4)
            hasher.combine(works)
        }
    }
}

// MARK: - TaskPriority Hashable Conformance

extension TaskPriority: @retroactive Hashable {}
