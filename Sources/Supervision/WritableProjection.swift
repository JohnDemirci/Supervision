//
//  WritableProjection.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

/// A projection type that enables property-like read/write syntax for batch mutations.
///
/// `WritableProjection` is returned by ``BatchBuilder``'s dynamic member lookup
/// and provides the actual getter and setter for property access.
///
/// ## Overview
///
/// When you write `batch.userName = "John"`, the following happens:
///
/// 1. `BatchBuilder.subscript(dynamicMember:)` returns a `WritableProjection`
/// 2. The assignment calls `WritableProjection.wrappedValue.set`
/// 3. The setter creates an `AnyMutation` and applies it
///
/// ## Reading and Writing
///
/// WritableProjection supports both reading and writing:
///
/// ```swift
/// context.modify { batch in
///     // Reading via wrappedValue getter
///     let current = batch.count.wrappedValue
///     // Or simply (Swift infers wrappedValue):
///     let count: Int = batch.count
///
///     // Writing via wrappedValue setter
///     batch.count = current + 1
/// }
/// ```
///
/// ## Nested Properties
///
/// WritableProjection uses `@dynamicMemberLookup` to support nested access:
///
/// ```swift
/// context.modify { batch in
///     batch.user.name = "John"           // Nested property
///     batch.user.address.city = "NYC"    // Deeply nested
/// }
/// ```
///
/// This works by appending key paths: `\State.user` + `\User.name` = `\State.user.name`
///
/// ## Implementation Notes
///
/// - The setter is `nonmutating` because mutations go through `mutateFn`
/// - Zero-copy reads via pointer dereference
/// - Thread-safe when used within the `@MainActor` context
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

    /// The current value at this key path, with read and write access.
    ///
    /// **Getter**: Reads the current value from state (zero-copy via pointer).
    ///
    /// ```swift
    /// let current = batch.count  // Reads state.count
    /// ```
    ///
    /// **Setter**: Applies a mutation to update the value.
    ///
    /// ```swift
    /// batch.count = 42  // Sets state.count = 42
    /// ```
    ///
    /// - Note: The setter is `nonmutating` because the mutation is applied
    ///   through the mutation function, not by mutating this struct.
    public var wrappedValue: Value {
        get {
            statePointer.pointee[keyPath: keyPath]
        }
        nonmutating set {
            mutateFn(.init(keyPath, newValue))
        }
    }

    /// Provides access to nested properties within the projected value.
    ///
    /// This enables chained property access like `batch.user.name`:
    ///
    /// ```swift
    /// context.modify { batch in
    ///     batch.user.name = "John"        // \State.user.name
    ///     batch.settings.theme = .dark    // \State.settings.theme
    /// }
    /// ```
    ///
    /// - Parameter nestedKeyPath: A key path from the current value to a nested property.
    /// - Returns: A new `WritableProjection` for the nested property.
    public subscript<NestedValue>(dynamicMember nestedKeyPath: WritableKeyPath<Value, NestedValue>) -> WritableProjection<State, NestedValue> {
        WritableProjection<State, NestedValue>(
            keyPath: keyPath.appending(path: nestedKeyPath),
            mutateFn: mutateFn,
            statePointer: statePointer
        )
    }
}
