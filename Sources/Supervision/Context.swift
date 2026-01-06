//
//  Context.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

/// A non-copyable context for safely reading and mutating feature state.
///
/// `Context` is passed to your feature's ``FeatureProtocol/process(action:context:)`` method
/// as a `borrowing` parameter. It provides zero-copy access to state for both reading and writing.
///
/// ## Overview
///
/// Use the context to read and mutate state within your action handler:
///
/// ```swift
/// func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
///     switch action {
///     case .increment:
///         context.state.count += 1
///         return .empty()
///
///     case .setName(let name):
///         context.modify(\.userName, to: name)
///         return .empty()
///     }
/// }
/// ```
///
/// ## Reading State
///
/// Access state properties directly via dynamic member lookup:
///
/// ```swift
/// let count = context.count           // Dynamic member lookup
/// let name = context.state.userName   // Via state property
/// let value = context.read(\.someKey) // Explicit read
/// ```
///
/// ## Mutating State
///
/// Several mutation patterns are supported:
///
/// ```swift
/// // Direct property assignment
/// context.state.count += 1
///
/// // KeyPath-based assignment
/// context.modify(\.userName, to: "John")
///
/// // In-place mutation for complex types
/// context.modify(\.items) { items in
///     items.append(newItem)
///     items.sort()
/// }
///
/// // Batch multiple mutations
/// context.modify { batch in
///     batch.set(\.isLoading, to: false)
///     batch.set(\.data, to: loadedData)
///     batch.set(\.error, to: nil)
/// }
/// ```
///
/// ## Equatable Optimization
///
/// When using `modify(_:to:)` with Equatable types, the mutation is skipped
/// if the new value equals the current value. This prevents unnecessary
/// SwiftUI view re-renders:
///
/// ```swift
/// context.modify(\.count, to: 5)  // Only triggers observation if count != 5
/// ```
///
/// ## Non-Copyable Design
///
/// Context is marked `~Copyable` to prevent it from escaping the `process` method.
/// This ensures state mutations are synchronous and contained:
///
/// ```swift
/// // This won't compile - Context cannot escape
/// func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
///     return .run { env in
///         context.state.count += 1  // Error: cannot capture borrowing parameter
///     }
/// }
///
/// // Mutate before returning Work
/// func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
///     context.state.isLoading = true  // OK: synchronous mutation
///     return .run { env in
///         // async work here
///     }
/// }
/// ```
///
/// ## Performance
///
/// All operations are `@inlinable` for optimal performance:
/// - **Reads**: Zero-copy via pointer dereference, O(1)
/// - **Mutations**: Direct pointer write, O(1)
/// - **Batching**: Groups mutations for logical clarity
/// - **Equatable check**: Skips no-op mutations
@MainActor
@dynamicMemberLookup
public struct Context<State>: ~Copyable {
    @usableFromInline
    internal let mutateFn: (AnyMutation<State>) -> Void

    @usableFromInline
    internal let statePointer: UnsafePointer<State>

    @inlinable
    internal init(
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafePointer<State>
    ) {
        self.mutateFn = mutateFn
        self.statePointer = statePointer
    }

    // MARK: - Zero-Copy Reads

    /// Provides direct access to state properties via dynamic member lookup.
    ///
    /// ```swift
    /// let userName = context.userName  // Same as context.state.userName
    /// let count = context.items.count  // Nested access works too
    /// ```
    ///
    /// - Parameter keyPath: A key path to a property on the state.
    /// - Returns: The value at the specified key path.
    @inlinable
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        statePointer.pointee[keyPath: keyPath]
    }

    /// Reads a value from state using a key path.
    ///
    /// ```swift
    /// let name = context.read(\.userName)
    /// ```
    ///
    /// - Parameter keyPath: A key path to the value to read.
    /// - Returns: The value at the specified key path.
    @inlinable
    public func read<Value>(_ keyPath: KeyPath<State, Value>) -> Value {
        statePointer.pointee[keyPath: keyPath]
    }

    @inlinable
    public var state: State {
        get {
            statePointer.pointee
        }
    }

    /// Sets an `Equatable` state property to a new value, only if it differs from the current value.
    ///
    /// This overload provides an optimization for `Equatable` types: if the new value
    /// equals the current value, no mutation occurs and SwiftUI observation is not triggered.
    /// This prevents unnecessary SwiftUI view refreshes.
    ///
    /// ```swift
    /// context.modify(\.count, to: 5)  // Only triggers if count != 5
    /// context.modify(\.name, to: name) // Only triggers if name changed
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - newValue: The new value to set.
    @inlinable
    public func modify<Value: Equatable>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        let oldValue = statePointer.pointee[keyPath: keyPath]
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    /// Sets a state property to a new value unconditionally.
    ///
    /// Unlike the Equatable overload, this always applies the mutation regardless
    /// of whether the value changed. Use this for non-Equatable types.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - newValue: The new value to set.
    @inlinable
    @_disfavoredOverload
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }

    /// Mutates a state property in-place with an Equatable check.
    ///
    /// The mutation is only applied if the resulting value differs from the original.
    /// This prevents unnecessary SwiftUI view refreshes.
    ///
    /// ```swift
    /// context.modify(\.count) { count in
    ///     count = max(0, count)  // Only triggers if value actually changed
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - mutation: A closure that mutates the value in place.
    @inlinable
    public func modify<Value: Equatable>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ mutation: (inout Value) -> Void
    ) {
        let oldValue = statePointer.pointee[keyPath: keyPath]
        var newValue = oldValue
        mutation(&newValue)
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    /// Mutates a non-Equatable state property in-place.
    ///
    /// Since the value is not Equatable, the mutation is always applied.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - mutation: A closure that mutates the value in place.
    @inlinable
    @_disfavoredOverload
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, _ mutation: (inout Value) -> Void) {
        var value = statePointer.pointee[keyPath: keyPath]
        mutation(&value)
        mutateFn(.init(keyPath, value))
    }

    // MARK: - Batching

    /// Performs multiple state mutations as a logical group.
    ///
    /// Use batching to express related mutations together:
    ///
    /// ```swift
    /// context.modify { batch in
    ///     batch.set(\.isLoading, to: false)
    ///     batch.set(\.data, to: response.data)
    ///     batch.set(\.lastUpdated, to: Date())
    ///     batch.set(\.error, to: nil)
    /// }
    /// ```
    ///
    /// - Parameter build: A closure that receives a ``BatchBuilder`` for setting values.
    ///
    /// - Note: Batching is for code organization. Each mutation is applied immediately;
    ///   there is no transactional rollback.
    @inline(never)
    public func modify(_ build: (borrowing BatchBuilder<State>) -> Void) {
        let mutateFn = self.mutateFn
        build(
            BatchBuilder<State>(
                mutateFn: { mutation in
                    mutateFn(mutation)
                },
                statePointer: statePointer
            )
        )
    }
}
