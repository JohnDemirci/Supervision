//
//  Supervisor.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import OSLog

@MainActor
@Observable
@dynamicMemberLookup
public final class Supervisor<Feature: FeatureProtocol> {
    public typealias State = Feature.State
    public typealias Action = Feature.Action
    public typealias Dependency = Feature.Dependency
    
    nonisolated
    private let logger: Logger
    
    public subscript <Subject>(dynamicMember keyPath: KeyPath<State, Subject>) -> Subject {
        state[keyPath: keyPath]
    }

    private let dependency: Dependency
    
    public let id: ReferenceIdentifier
    
    internal let feature: Feature

    /// The single source of truth for state
    /// - internal(set): Only Supervisor can reassign this property
    /// - Reading is safe and doesn't violate encapsulation
    internal(set) public var state: State

    // MARK: - Reentrancy Protection

    private var isProcessing = false
    private var queuedActions: [Action] = []

    // MARK: - Initialization

    init(
        id: ReferenceIdentifier,
        state: State,
        dependency: Dependency
    ) {
        self.id = id
        self.logger = .init(
            subsystem: "com.Supervision.\(Feature.self)",
            category: "Supervisor"
        )
        // Validate that State is a value type (best effort)
        let mirror = Mirror(reflecting: state)
        if mirror.displayStyle != .struct && mirror.displayStyle != .enum {
            logger.debug(
                """
                ⚠️ Warning: State should be a struct or enum (value type).
                Using reference types (classes) can lead to unexpected behavior.
                Current State type: \(type(of: state))
                """
            )
        }

        self.state = state
        self.dependency = dependency
        self.feature = Feature()
    }

    // MARK: - Action Processing

    /// Processes an action through the feature's logic
    /// Uses withUnsafePointer to provide zero-copy state access
    ///
    /// - Parameter action: The action to process
    ///
    /// ## Performance
    /// - Zero-copy state reads during feature processing
    /// - Immediate mutation visibility via pointer dereference
    /// - Batching support: use context.batch {} to combine mutations
    ///
    /// ## Safety
    /// - Reentrancy protection: prevents recursive send() calls
    /// - Pointer validity: guaranteed by withUnsafePointer scope
    /// - @MainActor: prevents concurrent access to state
    public func send(_ action: Action) {
        // Reentrancy protection: prevent send() from being called during process()
        guard !isProcessing else {
            #if DEBUG
            let logMessage: String = """
                ⚠️ Reentrancy detected: Cannot call send() while processing an action.
                Action queued for execution after current action completes.
                Action: \(action)
            """
            
            logger.debug("\(logMessage)")
            #endif
            queuedActions.append(action)
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
            processQueuedActions()
        }

        // Create a mutable pointer to our state and use it during process()
        // The pointer is valid for the entire scope of this closure
        // We use withUnsafeMutablePointer to avoid exclusivity violations
        withUnsafeMutablePointer(to: &self.state) { statePtr in
            // Batching support
            var isBatching = false
            var batchedMutations: [AnyMutation<State>] = []

            let context = Context<State>(
                mutateFn: { mutation in
                    if isBatching {
                        // Collect mutation for batch processing
                        batchedMutations.append(mutation)
                    } else {
                        // Apply mutation immediately through the pointer (not self.state)
                        // This avoids exclusivity violations
                        // Mutations trigger @Observable change notifications
                        mutation.apply(&statePtr.pointee)
                    }
                },
                statePointer: UnsafePointer(statePtr),
                enableBatchingFn: {
                    isBatching = true
                },
                flushBatchFn: {
                    // Apply all batched mutations at once
                    // This triggers only ONE @Observable notification for all mutations
                    for mutation in batchedMutations {
                        mutation.apply(&statePtr.pointee)
                    }
                    batchedMutations.removeAll()
                    isBatching = false
                }
            )

            // Process the action with zero-copy state access
            // Context is used synchronously, so statePtr remains valid
            feature.process(
                action: action,
                context: context,
                dependency: dependency
            )
        }
        // statePtr is no longer valid after this point
        // But Context is also no longer accessible (borrowing + ~Copyable)
    }

    // MARK: - Queue Processing

    private func processQueuedActions() {
        // Process any actions that were queued due to reentrancy
        while !queuedActions.isEmpty {
            let action = queuedActions.removeFirst()
            send(action)
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
