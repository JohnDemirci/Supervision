//
//  BatchBuilder.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

/// A non-copyable builder for performing multiple state mutations with ergonomic syntax.
///
/// `BatchBuilder` is used within ``Context/modify(_:)-6c794`` to group related
/// state changes together. It provides property-like syntax for setting values.
///
/// ## Overview
///
/// Use BatchBuilder to express multiple mutations as a logical group:
///
/// ```swift
/// func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
///     switch action {
///     case .dataLoaded(let data):
///         context.modify { batch in
///             batch.isLoading = false
///             batch.data = data
///             batch.lastUpdated = Date()
///             batch.error = nil
///         }
///         return .empty()
///     }
/// }
/// ```
///
/// ## Property-Like Syntax
///
/// BatchBuilder uses `@dynamicMemberLookup` to enable direct property assignment:
///
/// ```swift
/// context.modify { batch in
///     batch.userName = "John"      // Sets state.userName
///     batch.isEnabled = true       // Sets state.isEnabled
///     batch.user.email = "a@b.com" // Nested property access
/// }
/// ```
///
/// ## Reading Values
///
/// You can also read current values within the batch:
///
/// ```swift
/// context.modify { batch in
///     let current = batch.count    // Read current value
///     batch.count = current + 1    // Set new value
/// }
/// ```
///
/// ## Non-Copyable Design
///
/// BatchBuilder is marked `~Copyable` to prevent it from escaping the closure.
/// This ensures all mutations are applied synchronously within the batch scope.
///
/// ## Implementation Notes
///
/// - Each property assignment creates an `AnyMutation` applied immediately
/// - There is no transactional rollback; mutations are applied as they occur
/// - Batching is for code organization, not atomicity
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

    /// Provides read/write access to state properties via dynamic member lookup.
    ///
    /// This subscript returns a ``WritableProjection`` that enables property-like syntax:
    ///
    /// ```swift
    /// context.modify { batch in
    ///     batch.userName = "John"  // Calls this subscript, then WritableProjection's setter
    ///     let name = batch.userName // Reads via WritableProjection's getter
    /// }
    /// ```
    ///
    /// - Parameter keyPath: A writable key path to the state property.
    /// - Returns: A ``WritableProjection`` for reading and writing the value.
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<State, Value>) -> WritableProjection<State, Value> {
        WritableProjection(
            keyPath: keyPath,
            mutateFn: mutateFn,
            statePointer: statePointer
        )
    }

    // MARK: - Explicit Set Methods for Equatable Optimization

    /// Sets an Equatable state property, only if the value actually changed.
    ///
    /// This method provides an optimization for Equatable types: if the new value
    /// equals the current value, no mutation occurs and SwiftUI observation is not triggered.
    ///
    /// ```swift
    /// context.modify { batch in
    ///     batch.set(\.count, to: 42)  // Only triggers if count != 42
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - newValue: The new value to set.
    public func set<Value: Equatable>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        let oldValue = statePointer.pointee[keyPath: keyPath]
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    /// Sets a non-Equatable state property unconditionally.
    ///
    /// Since the value is not Equatable, the mutation is always applied.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - newValue: The new value to set.
    public func set<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }
}
