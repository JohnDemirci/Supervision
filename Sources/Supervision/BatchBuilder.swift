//
//  BatchBuilder.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

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
