//
//  BatchBuilder.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

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

    // MARK: - Explicit Set Methods for Equatable Optimization

    /// Sets the property at the given writable key path to a new value within the current batch,
    /// only applying the mutation if the value actually changes.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to a property on `State` to be updated.
    ///   - newValue: The new value to assign to the property referenced by `keyPath`.
    ///
    /// - Note: If the current value equals `newValue`, no mutation is performed.
    public func set<Value: Equatable>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        let oldValue = statePointer.pointee[keyPath: keyPath]
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    /// Sets the property at the given writable key path to a new value within the current batch,
    /// unconditionally applying the mutation.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the property on `State` that should be updated.
    ///   - newValue: The value to assign to the property referenced by `keyPath`.
    ///
    /// - Important: This method always records a mutation, which may trigger downstream updates
    ///   even if the effective value is the same. Prefer the `Equatable` overload when you want
    ///   to avoid unnecessary mutations for unchanged values.
    @_disfavoredOverload
    public func set<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }
}
