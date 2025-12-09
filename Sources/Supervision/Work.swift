//
//  Work.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

import Foundation


/// A generic structure representing a unit of asynchronous work that can be executed with a given environment.
///
/// `Work` encapsulates tasks that can be cancelled, mapped, and composed together in a functional programming style.
/// Each work unit can optionally have a cancellation identifier and error handling.
///
/// ## Type Parameters
/// - `Output`: The type of value produced when the work completes successfully
/// - `Environment`: The type of environment/context required to execute the work
public struct Work<Output, Environment>: Sendable {
    enum Operation {
        case none
        case cancellation(String)
        case fireAndForget(
            TaskPriority?,
            @Sendable (Environment) async throws -> Void
        )
        case task(
            TaskPriority?,
            @Sendable (Environment) async throws -> Output
        )
    }
    
    let cancellationID: String?
    let operation: Operation
    let onError: (@Sendable (Error) -> Output)?
    
    init(
        cancellationID: String? = nil,
        operation: Operation,
        fireAndForget: Bool = false,
        onError: (@Sendable (Error) -> Output)? = nil
    ) {
        self.operation = operation
        self.onError = onError
        self.cancellationID = cancellationID
    }
}

extension Work {
    public static func empty<O, E>() -> Work<O, E> {
        Work<O, E>.init(operation: .none)
    }
    
    public static func cancel(_ id: String) -> Work<Output, Environment> {
        Work(
            cancellationID: nil,
            operation: .cancellation(id),
            onError: nil
        )
    }
    
    public static func fireAndForget(
        priority: TaskPriority? = nil,
        _ body: @Sendable @escaping (Environment) async throws -> Void
    ) -> Work<Output, Environment> {
        Work<Output, Environment>(
            operation: .fireAndForget(priority, body)
        )
    }
    
    public static func run<Value>(
        priority: TaskPriority? = nil,
        _ body: @Sendable @escaping (Environment) async throws -> Value,
        toAction: @Sendable @escaping (Result<Value, Error>) -> Output
    ) -> Work<Output, Environment> {
        Work<Output, Environment>(
            operation: .task(priority, { env in
                do {
                    let value = try await body(env)
                    return toAction(.success(value))
                } catch {
                    return toAction(.failure(error))
                }
            })
        )
    }
    
    public static func run(
        priority: TaskPriority? = nil,
        _ body: @Sendable @escaping (Environment) async throws -> Output
    ) -> Work<Output, Environment> {
        Work<Output, Environment>.init(operation: .task(priority, body))
    }
}

extension Work {
    public func map<NewOutput>(
        _ transform: @Sendable @escaping (Output) -> NewOutput
    ) -> Work<NewOutput, Environment> {
        switch self.operation {
        case .none:
            preconditionFailure("attempting to map a non-task work unit")
            
        case .cancellation:
            preconditionFailure("attempting to map a non-task work unit")
            
        case .fireAndForget:
            preconditionFailure("attempting to map a fire-and-forget. This is a logical error")
            
        case .task(let priority, let work):
            return Work<NewOutput, Environment>.init(
                cancellationID: cancellationID,
                operation: .task(priority, { env in
                    let output = try await work(env)
                    return transform(output)
                }),
                onError: nil
            )
        }
    }
    
    public func `catch`(
        _ transform: @Sendable @escaping (Error) -> Output
    ) -> Work<Output, Environment> {
        Work<Output, Environment>(
            cancellationID: cancellationID,
            operation: operation,
            onError: { error in
                transform(error)
            }
        )
    }
    
    public func flatMap<NewOutput>(
        _ transform: @Sendable @escaping (Output) -> Work<NewOutput, Environment>
    ) -> Work<NewOutput, Environment> {
        switch operation {
        case .none:
            return .empty()
            
        case .cancellation:
            return .empty()
            
        case .fireAndForget:
            preconditionFailure("flat mapping fire-and-forget")
            
        case .task(let priority, let work):
            return Work<NewOutput, Environment>(
                operation: .task(priority, { env in
                    let newWork = try await transform(work(env))
                    
                    switch newWork.operation {
                    case .none, .cancellation, .fireAndForget:
                        preconditionFailure("cannot flat map into a work unit that is empty")
                    case .task(_, let action):
                        return try await action(env)
                    }
                })
            )
        }
    }
    
    /// Adds a cancellation ID to the work.
    /// - Note: Omits the cancellation if the operation is not ``Operation.task``
    ///
    /// - Parameters:
    ///    - id: String value for the cancellationID
    public func cancellable(id: String) -> Work<Output, Environment> {
        Work(cancellationID: id, operation: operation, onError: onError)
    }
}
