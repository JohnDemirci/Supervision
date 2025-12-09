//
//  Supervisor.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Combine
import Foundation
import OSLog

@MainActor
@Observable
@dynamicMemberLookup
public final class Supervisor<Feature: FeatureProtocol> {
    public typealias Action = Feature.Action
    public typealias Dependency = Feature.Dependency
    public typealias State = Feature.State
    
    nonisolated
    private let logger: Logger

    private let actionContinuation: AsyncStream<Work<Action, Dependency>>.Continuation
    private let actionStream: AsyncStream<Work<Action, Dependency>>
    private let dependency: Dependency
    private let worker: Worker<Action, Dependency>
    
    private var processingTask: Task<Void, Never>?
    private var workTasks: [String: Task<Void, Never>] = [:]

    public let id: ReferenceIdentifier

    internal let feature: Feature
    internal(set) public var state: State

    // MARK: - Initialization

    internal init(
        id: ReferenceIdentifier,
        state: State,
        dependency: Dependency
    ) {
        self.id = id
        self.logger = .init(
            subsystem: "com.Supervision.\(Feature.self)",
            category: "Supervisor"
        )
        
        let mirror = Mirror(reflecting: state)
        if mirror.displayStyle != .struct && mirror.displayStyle != .enum {
            logger.error(
                """
                ⚠️ Warning: State should be a struct or enum (value type).
                Using reference types (classes) can lead to unexpected behavior.
                Current State type: \(type(of: state))
                """
            )
        }

        self.state = state
        self.dependency = dependency
        self.worker = .init()
        self.feature = Feature()
        
        let (stream, continuation) = AsyncStream.makeStream(of: Work<Action, Dependency>.self, bufferingPolicy: .unbounded)
        self.actionStream = stream
        self.actionContinuation = continuation

         self.processingTask = Task { [weak self] in
             for await work in stream {
                 guard let self else { return }
                 await self.processAsyncWork(work)
             }
         }
    }
    
    isolated deinit {
         actionContinuation.finish()
         processingTask?.cancel()

         for (_, task) in workTasks {
             task.cancel()
         }
         workTasks.removeAll()
     }
    
    public subscript <Subject>(dynamicMember keyPath: KeyPath<State, Subject>) -> Subject {
        state[keyPath: keyPath]
    }

    /// Dispatches an action to the feature for processing.
    ///
    /// This method processes the given action through the feature's `process(action:context:)` method,
    /// which may result in state mutations and/or asynchronous work being scheduled.
    ///
    /// - Parameter action: The action to process. The action type is defined by the feature's
    ///   `Action` associated type.
    ///
    /// - Note: This method is synchronous for immediate state updates, but any resulting
    ///   asynchronous work will be scheduled and executed separately. Use cancellation IDs
    ///   in your feature's work definitions to manage long-running tasks.
    public func send(_ action: Action) {
        let work = withUnsafeMutablePointer(to: &state) { pointer in
            // Pointer valid within the scope
            // Context is ~Copyable and never escapes
            // Everything in here us synchronous.
            let context = Context<Feature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafeMutablePointer(pointer)
            )
            // context is passed as a borrowing
            return feature.process(action: action, context: context)
            
            // work is returned it has no reference to context or the pointer
        }
        
        switch work.operation {
        case .none:
            return
        case .cancellation(let id):
            workTasks[id]?.cancel()
        case .task, .fireAndForget:
            actionContinuation.yield(work)
        }
    }
}

// MARK: - Convenience Initializer

extension Supervisor where State: Identifiable {
    public convenience init(
        state: State,
        dependency: Dependency
    ) {
        self.init(
            id: ReferenceIdentifier(id: state.id as AnyHashable),
            state: state,
            dependency: dependency
        )
    }
}

extension Supervisor {
    public convenience init(
        state: State,
        dependency: Dependency
    ) {
        self.init(
            id: ReferenceIdentifier(id: ObjectIdentifier(Supervisor<Feature>.self) as AnyHashable),
            state: state,
            dependency: dependency
        )
    }
}

extension Supervisor {
    private func processAsyncWork(_ work: Work<Action, Dependency>) async {
        switch work.operation {
        case .none:
            return
            
        case .cancellation(let id):
            workTasks[id]?.cancel()
            return
            
        case .fireAndForget:
            Task {
                _ = await worker.run(work, using: dependency)
            }
            return

        case .task:
            let workId = if let cancellationID = work.cancellationID {
                cancellationID
            } else {
                UUID().uuidString
            }
            
            let workTask = Task { @MainActor [weak self] in
                guard let self else { return }

                let resultAction = await self.worker.run(
                    work,
                    using: self.dependency
                )
                defer {
                    self.workTasks.removeValue(forKey: workId)
                }

                if let resultAction, !Task.isCancelled {
                    self.send(resultAction)
                }
            }

            workTasks[workId] = workTask

            await workTasks[workId]?.value
        }
    }
}
