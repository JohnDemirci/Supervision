//
//  Context.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

@MainActor
@dynamicMemberLookup
public struct Context<State>: ~Copyable {
    @usableFromInline
    internal let mutateFn: (AnyMutation<State>) -> Void

    @usableFromInline
    internal let statePointer: UnsafeMutablePointer<State>

    @inlinable
    internal init(
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafeMutablePointer<State>
    ) {
        self.mutateFn = mutateFn
        self.statePointer = statePointer
    }

    // MARK: - Zero-Copy Reads

    @inlinable
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        statePointer.pointee[keyPath: keyPath]
    }

    @inlinable
    public func read<Value>(_ keyPath: KeyPath<State, Value>) -> Value {
        statePointer.pointee[keyPath: keyPath]
    }

    @inlinable
    public var state: State {
        statePointer.pointee
    }

    // MARK: - Mutations

    @inlinable
    public func modify<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }

    @inlinable
    public func modify<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ modify: (inout Value) -> Void
    ) {
        modify(&statePointer.pointee[keyPath: keyPath])
    }

    // MARK: - Batching

    @inline(never)
    public func modify(_ build: (borrowing BatchBuilder<State>) -> Void) {
        build(
            BatchBuilder<State>(
                mutateFn: mutateFn,
                statePointer: statePointer
            )
        )
    }
}
