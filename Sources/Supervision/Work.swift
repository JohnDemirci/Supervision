//
//  Work.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

import Foundation

public protocol Work<Action, Environment, CancellationID>: ~Copyable, Sendable {
    associatedtype Action: Sendable
    associatedtype Environment
    associatedtype CancellationID: Cancellation = Never
}

public enum Kind<Action: Sendable, Dependency, CancellationID: Cancellation>: Sendable {
    case done
    case cancel(Cancel<Action, Dependency, CancellationID>)
    case run(any RunnableWork<Action, Dependency, CancellationID>)
    case subscribe(any SubscriptionWork<Action, Dependency, CancellationID>)
    case fireAndForget(FireAndForget<Action, Dependency, CancellationID>)
}

extension Kind {
    public typealias Environment = Dependency

    public static func cancellation(_ id: CancellationID) -> Self {
        .cancel(Cancel<Action, Environment, CancellationID>(id: id))
    }

    public static func run<Value: Sendable>(
        name: String? = nil,
        priority: TaskPriority? = nil,
        cancellationID: CancellationID? = nil,
        produce: @Sendable @escaping (Environment) async throws -> Value,
        transform: @Sendable @escaping (Result<Value, Error>) -> Action
    ) -> Self {
        .run(
            Run<Action, Environment, CancellationID, Value>(
                name: name,
                priority: priority,
                cancellationID: cancellationID,
                produce: produce,
                transform: transform
            )
        )
    }

    public static func subscribe<Value: Sendable>(
        name: String? = nil,
        cancellationID: CancellationID,
        produce: @Sendable @escaping (Environment) async throws -> AsyncThrowingStream<Value, Error>,
        transform: @Sendable @escaping (Result<Value, Error>) -> Action
    ) -> Self {
        .subscribe(
            Subscribe<Action, Environment, CancellationID, Value>(
                name: name,
                cancellationID: cancellationID,
                produce: produce,
                transform: transform
            )
        )
    }

    public static func fireAndForget(
        priority: TaskPriority? = nil,
        produce: @Sendable @escaping (Environment) async throws -> Void
    ) -> Self {
        .fireAndForget(
            FireAndForget<Action, Environment, CancellationID>(
                priority: priority,
                work: produce
            )
        )
    }
}

public protocol RunnableWork<Action, Environment, CancellationID>: Work {
    var name: String? { get }
    var priority: TaskPriority? { get }
    var cancellationID: CancellationID? { get }

    func execute(with env: Environment) async -> Action
}

extension RunnableWork {
    public static func run<Value: Sendable>(
        name: String? = nil,
        priority: TaskPriority? = nil,
        cancellationID: CancellationID? = nil,
        produce: @Sendable @escaping (Environment) async throws -> Value,
        transform: @Sendable @escaping (Result<Value, Error>) -> Action
    ) -> some RunnableWork<Action, Environment, CancellationID> {
        Run<Action, Environment, CancellationID, Value>(
            name: name,
            priority: priority,
            cancellationID: cancellationID,
            produce: produce,
            transform: transform
        )
    }
}

public protocol SubscriptionWork<Action, Environment, CancellationID>: Work {
    var name: String? { get }
    var cancellationID: CancellationID { get }

    associatedtype Value
    associatedtype ActionSequence: AsyncSequence where ActionSequence.Element == Action
    func subscribe(with env: Environment) async throws -> ActionSequence

    func receive(value: Value) -> Action
    func receive(error: Error) -> Action
}

public struct Done<
    Action: Sendable,
    Environment,
    CancellationID: Cancellation
>: Work {
    public init() { }
}

public struct Cancel<
    Action: Sendable,
    Environment,
    CancellationID: Cancellation
>: Work {
    let id: CancellationID

    public init(id: CancellationID) {
        self.id = id
    }
}

public struct Run<
    Action: Sendable,
    Environment,
    CancellationID: Cancellation,
    Value: Sendable
>: RunnableWork {
    public let name: String?
    public let priority: TaskPriority?
    public let cancellationID: CancellationID?
    let produce: @Sendable (Environment) async throws -> Value
    let transform: @Sendable (Result<Value, Error>) -> Action

    public init(
        name: String? = nil,
        priority: TaskPriority? = nil,
        cancellationID: CancellationID? = nil,
        produce: @Sendable @escaping (Environment) async throws -> Value,
        transform: @Sendable @escaping (Result<Value, Error>) -> Action
    ) {
        self.name = name
        self.priority = priority
        self.cancellationID = cancellationID
        self.produce = produce
        self.transform = transform
    }

    @concurrent
    public func execute(with env: Environment) async -> Action {
        do {
            let value = try await produce(env)
            return transform(.success(value))
        } catch {
            return transform(.failure(error))
        }
    }

    public func receive(value: Value) -> Action {
        transform(.success(value))
    }

    public func receive(error: Error) -> Action {
        transform(.failure(error))
    }
}

public struct Subscribe<
    Action: Sendable,
    Environment,
    CancellationID: Cancellation,
    Value: Sendable
>: SubscriptionWork, Sendable {
    public let name: String?
    public let cancellationID: CancellationID
    let produce: @Sendable (Environment) async throws -> AsyncThrowingStream<Value, Error>
    let transform: @Sendable (Result<Value, Error>) -> Action

    public init(
        name: String? = nil,
        cancellationID: CancellationID,
        produce: @Sendable @escaping (Environment) async throws -> AsyncThrowingStream<Value, Error>,
        transform: @Sendable @escaping (Result<Value, Error>) -> Action
    ) {
        self.name = name
        self.cancellationID = cancellationID
        self.produce = produce
        self.transform = transform
    }

    @concurrent
    public func subscribe(with environment: Environment) async throws -> some AsyncSequence<Action, Error> {
        try await produce(environment)
            .map { [transform] value in
                transform(.success(value))
            }
    }

    public func receive(value: Value) -> Action {
        transform(.success(value))
    }

    public func receive(error: Error) -> Action {
        transform(.failure(error))
    }
}

public struct FireAndForget<Action: Sendable, Environment, CancellationID: Cancellation>: Work {
    let priority: TaskPriority?
    let work: @Sendable (Environment) async throws -> Void

    public init(
        priority: TaskPriority?,
        work: @Sendable @escaping (Environment) async throws -> Void
    ) {
        self.priority = priority
        self.work = work
    }

    @concurrent
    func execute(with environment: Environment) async {
        do {
            _ = try await work(environment)
        } catch {
            // nothing we do not care
        }
    }
}

extension Never: Cancellation {}
