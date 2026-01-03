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
/// ## Non-Copyable Design
///
/// Context is marked `~Copyable` to prevent it from escaping the `process` method.
/// This ensures state mutations are synchronous and contained:
///
/// ```swift
/// // ❌ This won't compile - Context cannot escape
/// func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
///     return .run { env in
///         context.state.count += 1  // Error: cannot capture borrowing parameter
///     }
/// }
///
/// // ✅ Mutate before returning Work
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
@MainActor
@dynamicMemberLookup
public struct Context<State>: ~Copyable {
    @usableFromInline
    internal let mutateFn: (AnyMutation<State>) -> Void

    @usableFromInline
    internal let statePointer: UnsafeMutablePointer<State>

    @usableFromInline
    internal let onMutate: () -> Void

    @inlinable
    internal init(
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafeMutablePointer<State>,
        onMutate: @escaping () -> Void = {}
    ) {
        self.mutateFn = mutateFn
        self.statePointer = statePointer
        self.onMutate = onMutate
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

    /// The current state, available for reading and direct mutation.
    ///
    /// ```swift
    /// // Reading
    /// let count = context.state.count
    ///
    /// // Mutating
    /// context.state.count += 1
    /// context.state.userName = "John"
    /// ```
    @inlinable
    public var state: State {
        get {
            statePointer.pointee
        }
        nonmutating set {
            onMutate()
            statePointer.pointee = newValue
        }
    }

    // MARK: - Mutations

    /// Sets a state property to a new value using a key path.
    ///
    /// ```swift
    /// context.modify(\.userName, to: "John")
    /// context.modify(\.isLoading, to: true)
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - newValue: The new value to set.
    @inlinable
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        onMutate()
        mutateFn(.init(keyPath, newValue))
    }

    /// Mutates a state property in-place using a closure.
    ///
    /// Use this for complex mutations on collections or nested types:
    ///
    /// ```swift
    /// context.modify(\.items) { items in
    ///     items.append(newItem)
    ///     items.removeAll { $0.isExpired }
    ///     items.sort(by: { $0.date > $1.date })
    /// }
    ///
    /// context.modify(\.user) { user in
    ///     user.name = "John"
    ///     user.email = "john@example.com"
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property to modify.
    ///   - modify: A closure that receives the value as `inout` for mutation.
    @inlinable
    public func modify<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ modify: (inout Value) -> Void
    ) {
        onMutate()
        modify(&statePointer.pointee[keyPath: keyPath])
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
        let onMutate = self.onMutate
        let mutateFn = self.mutateFn
        build(
            BatchBuilder<State>(
                mutateFn: { mutation in
                    onMutate()
                    mutateFn(mutation)
                },
                statePointer: statePointer
            )
        )
    }
}
