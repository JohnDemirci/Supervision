//
//  Context.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

/// A non-copyable value type that encapsulates the current state of a feature,
/// enabling controlled reads and mutations.
///
/// ```swift
/// func process(action: Action, context: borrowing Context<State>) -> FeatureWork
/// ```
/// You do not typically create a `Context`; it is provided by ``Feature`` when `process` is called.
@dynamicMemberLookup
public struct Context<State>: ~Copyable {
    @usableFromInline
    internal let mutateFn: (AnyMutation<State>) -> Void

    @usableFromInline
    internal let statePointer: UnsafePointer<State>

    public let id: ReferenceIdentifier

    @inlinable
    internal init(
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafePointer<State>,
        id: ReferenceIdentifier
    ) {
        self.mutateFn = mutateFn
        self.statePointer = statePointer
        self.id = id
    }

    // MARK: - Zero-Copy Reads

    @inlinable
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        state[keyPath: keyPath]
    }

    @inlinable
    @inline(__always)
    public var state: State {
        _read {
            yield statePointer.pointee
        }
    }

    /// Modifies the state with the matching keypath
    ///
    /// - Note: if the new value equals to the old value, there is no effect.
    ///
    /// - Parameters:
    ///    - keyPath: The keypath of the property to modify
    ///    - newValue: The new value to set to the given keypath
    @inlinable
    public func modify<Value: Equatable>(
        _ keyPath: WritableKeyPath<State, Value>,
        to newValue: Value
    ) {
        let oldValue = state[keyPath: keyPath]
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    /// Modifies the state with the matching keypath
    ///
    /// - Parameters:
    ///    - keyPath: The keypath of the property to modify
    ///    - newValue: The new value to set to the given keypath
    @inlinable
    @_disfavoredOverload
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }

    /// Modifies a writable property of the feature state in place using a mutation closure,
    /// skipping no-op updates when the value does not change.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property on `State` that you want to modify.
    ///   - mutation: A closure that receives the current value by `inout` and can mutate it.
    ///
    /// - Important: Because `Value` conforms to `Equatable`, this method avoids unnecessary
    ///   state updates by not emitting a mutation when the resulting value equals the original.
    ///
    /// - SeeAlso: ``modify(_:to:)-5282a`` for directly setting a new value.
    /// - SeeAlso: ``modify(_:_:)-3qfdj`` for the non-`Equatable` variant that always applies the mutation.
    @inlinable
    public func modify<Value: Equatable>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ mutation: (inout Value) -> Void
    ) {
        let oldValue = state[keyPath: keyPath]
        var newValue = oldValue
        mutation(&newValue)
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    /// Modifies a writable property of the feature state in place using a mutation closure.
    ///
    /// This overload allows you to mutate the value at the given key path without requiring
    /// `Value` to conform to `Equatable`. The current value is read from state, passed as an
    /// `inout` parameter to your closure for mutation, and the resulting value is then applied
    /// as a state mutation.
    ///
    /// - Important: The mutation is applied regardless of whether the resulting value is equal
    ///   to the original value. If you want to skip no-op updates when values are unchanged,
    ///   use the `Equatable`-constrained overload instead.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property on `State` that you want to modify.
    ///   - mutation: A closure that receives the current value by `inout` and can modify it.
    ///
    /// - SeeAlso: ``modify(_:to:)-5282a``
    /// - SeeAlso: ``modify(_:_:)-3qfdj`` (the `Equatable`-constrained variant that skips no-op updates)
    @inlinable
    @_disfavoredOverload
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, _ mutation: (inout Value) -> Void) {
        var value = state[keyPath: keyPath]
        mutation(&value)
        mutateFn(.init(keyPath, value))
    }

    /// Applies state mutations in a single, cohesive operation.
    ///
    /// Example:
    /// ```swift
    /// context.modify { builder in
    ///     builder.set(\.title, to: "Updated")
    ///     builder.set(\.isEnabled, to: true)
    /// }
    /// ```
    ///
    /// - Parameter build: A closure that receives a borrowing `BatchBuilder<State>` used to
    ///   compose multiple mutations.
    ///
    /// - SeeAlso: ``modify(_:to:)-5282a``
    /// - SeeAlso: ``modify(_:_:)-3qfdj`` (the `Equatable`-constrained variant)
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
