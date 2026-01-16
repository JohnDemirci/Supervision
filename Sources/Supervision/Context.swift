//
//  Context.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

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

    @inlinable
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        state[keyPath: keyPath]
    }

    @inlinable
    public var state: State {
        @inlinable
        _read {
            yield statePointer.pointee
        }
    }

    @inlinable
    public func modify<Value: Equatable>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        let oldValue = state[keyPath: keyPath]
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    @inlinable
    @_disfavoredOverload
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }

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

    @inlinable
    @_disfavoredOverload
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, _ mutation: (inout Value) -> Void) {
        var value = state[keyPath: keyPath]
        mutation(&value)
        mutateFn(.init(keyPath, value))
    }

    // MARK: - Batching

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
