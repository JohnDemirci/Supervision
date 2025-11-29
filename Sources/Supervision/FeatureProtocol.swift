//
//  FeatureProtocol.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

public protocol FeatureProtocol {
    associatedtype State
    associatedtype Action
    associatedtype Dependency

    func process(action: Action, context: borrowing Context<State>, dependency: Dependency)

    init()
}

/// Context provides controlled access to state during feature processing.
/// Uses UnsafePointer for zero-copy reads with immediate mutation visibility.
///
/// ## Performance
/// - Read: O(1) - zero-copy pointer dereference
/// - Mutation: O(1) - direct property update
/// - Batching: Combine multiple mutations into a single @Observable notification
///
/// ## Safety
/// - Only valid during synchronous `process()` execution
/// - ~Copyable: cannot be stored or copied (compile-time enforced)
/// - Non-Sendable: cannot be captured in async contexts (compile-time enforced)
/// - @MainActor serialization prevents race conditions
@dynamicMemberLookup
public struct Context<State>: ~Copyable {
    /// Applies a mutation to the state
    internal let mutateFn: (AnyMutation<State>) -> Void

    /// Direct pointer to Supervisor's state storage
    /// SAFETY: Only valid during the process() call on @MainActor
    internal let statePointer: UnsafePointer<State>

    /// Enables batching mode
    internal let enableBatchingFn: () -> Void

    /// Flushes batched mutations and disables batching
    internal let flushBatchFn: () -> Void

    internal init(
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafePointer<State>,
        enableBatchingFn: @escaping () -> Void,
        flushBatchFn: @escaping () -> Void
    ) {
        self.mutateFn = mutateFn
        self.statePointer = statePointer
        self.enableBatchingFn = enableBatchingFn
        self.flushBatchFn = flushBatchFn
    }

    // MARK: - Dynamic Member Lookup (Zero-Copy Reads)

    /// Enables read-only property access via `context.propertyName` syntax
    /// - Returns: Current value with zero-copy performance
    /// - Note: Mutations are immediately visible to subsequent reads
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        // TRUE zero-copy: directly reads from Supervisor's state storage
        statePointer.pointee[keyPath: keyPath]
    }

    // MARK: - Mutation API

    /// Explicitly mutates a state property at the given keyPath
    /// - Parameters:
    ///   - keyPath: The property to mutate
    ///   - value: The new value
    /// - Note: Mutations trigger @Observable notifications and are immediately visible
    public func mutate<Value>(_ keyPath: WritableKeyPath<State, Value>, to value: Value) {
        mutateFn(.init(keyPath, value))
    }

    /// Returns the current value at the given keyPath (zero-copy)
    /// - Parameter keyPath: The property to read
    /// - Returns: Current value
    public func read<Value>(_ keyPath: KeyPath<State, Value>) -> Value {
        statePointer.pointee[keyPath: keyPath]
    }

    /// Mutates a value by applying a transform to its current value
    /// - Parameters:
    ///   - keyPath: The property to mutate
    ///   - transform: Function that transforms the current value to a new value
    /// - Note: More efficient than separate read + mutate calls
    ///
    /// Example:
    /// ```swift
    /// context.transform(\.counter) { $0 + 1 }
    /// ```
    public func transform<Value>(_ keyPath: WritableKeyPath<State, Value>, _ transform: (Value) -> Value) {
        let currentValue = statePointer.pointee[keyPath: keyPath]
        let newValue = transform(currentValue)
        mutateFn(.init(keyPath, newValue))
    }

    /// Returns the entire current state
    /// - Returns: A copy of the complete state
    /// - Note: Creates one copy. Prefer accessing specific properties when possible.
    public var currentState: State {
        statePointer.pointee
    }

    // MARK: - Batching

    /// Batches multiple mutations into a single @Observable notification
    /// - Parameter mutations: Closure containing mutations to batch
    ///
    /// ## Performance Benefit
    /// Without batching:
    /// ```swift
    /// context.mutate(\.a, to: 1)  // Triggers @Observable notification
    /// context.mutate(\.b, to: 2)  // Triggers @Observable notification
    /// context.mutate(\.c, to: 3)  // Triggers @Observable notification
    /// // Total: 3 notifications, 3 potential UI updates
    /// ```
    ///
    /// With batching:
    /// ```swift
    /// context.batch {
    ///     context.mutate(\.a, to: 1)
    ///     context.mutate(\.b, to: 2)
    ///     context.mutate(\.c, to: 3)
    /// }
    /// // Total: 1 notification, 1 UI update
    /// ```
    ///
    /// ## Immediate Visibility
    /// Mutations inside the batch are NOT immediately visible to reads within the same batch:
    /// ```swift
    /// context.batch {
    ///     context.mutate(\.counter, to: 5)
    ///     print(context.counter)  // Still reads old value!
    /// }
    /// // After batch completes, counter is 5
    /// ```
    ///
    /// If you need immediate visibility, don't use batch() or flush partially:
    /// ```swift
    /// context.mutate(\.counter, to: 5)  // Not batched
    /// print(context.counter)  // Reads 5 immediately
    ///
    /// context.batch {
    ///     context.mutate(\.a, to: 1)
    ///     context.mutate(\.b, to: 2)
    /// }  // These are batched together
    /// ```
    public func batch(_ mutations: () -> Void) {
        enableBatchingFn()
        defer { flushBatchFn() }
        mutations()
    }

    /// Batches multiple mutations using a builder pattern
    /// - Parameter build: Closure that receives a BatchBuilder for ergonomic state mutations
    ///
    /// ## Ergonomic API
    /// This provides a more ergonomic way to batch mutations without exposing `inout State`:
    /// ```swift
    /// context.batch { state in
    ///     state.firstName = "John"
    ///     state.lastName = "Doe"
    ///     state.age = 30
    /// }
    /// // Total: 1 @Observable notification for all 3 mutations
    /// ```
    ///
    /// ## Safety
    /// - Does NOT expose `inout State` publicly (maintains internal(set) protection)
    /// - Uses KeyPath-based setters internally
    /// - All mutations applied atomically in one @Observable notification
    /// - Builder is ~Copyable and borrowing (cannot escape closure)
    ///
    /// ## Comparison with context.mutate()
    /// Without builder:
    /// ```swift
    /// context.batch {
    ///     context.mutate(\.firstName, to: "John")
    ///     context.mutate(\.lastName, to: "Doe")
    ///     context.mutate(\.age, to: 30)
    /// }
    /// ```
    ///
    /// With builder (more ergonomic):
    /// ```swift
    /// context.batch { state in
    ///     state.firstName = "John"
    ///     state.lastName = "Doe"
    ///     state.age = 30
    /// }
    /// ```
    ///
    /// ## Important Notes
    /// - Mutations are NOT immediately visible within the batch
    /// - Reading state through builder reads current state (not pending mutations)
    /// - Builder can only be used for setting values, not complex transformations
    public func batch(_ build: (borrowing BatchBuilder<State>) -> Void) {
        enableBatchingFn()
        defer { flushBatchFn() }

        let builder = BatchBuilder<State>(
            mutateFn: mutateFn,
            statePointer: statePointer
        )
        build(builder)
    }
}

/// Type-erased mutation that can be applied to state
struct AnyMutation<State> {
    var apply: (inout State) -> Void

    init<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ value: Value
    ) {
        self.apply = { state in
            state[keyPath: keyPath] = value
        }
    }
}

/// Builder for batching state mutations with ergonomic syntax
///
/// Provides property setter syntax while maintaining internal(set) protection.
/// Never exposes `inout State` publicly - uses KeyPath-based mutations internally.
///
/// ## Design
/// - ~Copyable: cannot be stored or copied (compile-time enforced)
/// - borrowing: cannot escape the batch closure
/// - @dynamicMemberLookup: enables `builder.property = value` syntax
/// - Internally collects mutations as `AnyMutation<State>` objects
///
/// ## Safety
/// - Does NOT provide direct mutable access to state
/// - All mutations go through the existing mutation infrastructure
/// - Maintains internal(set) protection on Supervisor.state
@dynamicMemberLookup
public struct BatchBuilder<State>: ~Copyable {
    private let mutateFn: (AnyMutation<State>) -> Void
    private let statePointer: UnsafePointer<State>

    internal init(
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafePointer<State>
    ) {
        self.mutateFn = mutateFn
        self.statePointer = statePointer
    }

    /// Provides write-only property access via subscript setter
    /// - Parameter keyPath: The property to mutate
    /// - Returns: A WritableProjection that captures the setter
    ///
    /// This enables the ergonomic syntax:
    /// ```swift
    /// builder.firstName = "John"  // Uses this subscript
    /// ```
    ///
    /// The setter is called when you assign a value, which internally
    /// creates an AnyMutation and applies it through the mutation system.
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<State, Value>) -> WritableProjection<State, Value> {
        WritableProjection(
            keyPath: keyPath,
            mutateFn: mutateFn,
            statePointer: statePointer
        )
    }
}

/// Helper type that provides property-like setter syntax for BatchBuilder
///
/// This enables `builder.property = value` syntax by capturing the WritableKeyPath
/// and providing a setter that applies the mutation through the mutation system.
///
/// ## Implementation Detail
/// Swift's @dynamicMemberLookup with subscript can return a type with a setter.
/// When you write `builder.property = value`:
/// 1. subscript(dynamicMember:) is called, returning a WritableProjection
/// 2. The setter on WritableProjection is called with the new value
/// 3. The setter creates an AnyMutation and applies it
@dynamicMemberLookup
public struct WritableProjection<State, Value> {
    private let keyPath: WritableKeyPath<State, Value>
    private let mutateFn: (AnyMutation<State>) -> Void
    private let statePointer: UnsafePointer<State>

    internal init(
        keyPath: WritableKeyPath<State, Value>,
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafePointer<State>
    ) {
        self.keyPath = keyPath
        self.mutateFn = mutateFn
        self.statePointer = statePointer
    }

    /// Getter: Reads current state value (zero-copy)
    /// Allows reading within batch: `let current = builder.firstName`
    public var wrappedValue: Value {
        get {
            statePointer.pointee[keyPath: keyPath]
        }
        nonmutating set {
            // Setter: Creates and applies mutation
            mutateFn(.init(keyPath, newValue))
        }
    }

    /// Provides nested property access for complex state structures
    /// Enables: `builder.user.name = "John"`
    public subscript<NestedValue>(dynamicMember nestedKeyPath: WritableKeyPath<Value, NestedValue>) -> WritableProjection<State, NestedValue> {
        WritableProjection<State, NestedValue>(
            keyPath: keyPath.appending(path: nestedKeyPath),
            mutateFn: mutateFn,
            statePointer: statePointer
        )
    }
}
