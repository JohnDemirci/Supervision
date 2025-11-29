//
//  WritableProjection.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

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
