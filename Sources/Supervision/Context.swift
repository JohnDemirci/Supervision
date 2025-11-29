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
    internal let statePointer: UnsafePointer<State>

    @usableFromInline
    internal let enableBatchingFn: () -> Void

    @usableFromInline
    internal let flushBatchFn: () -> Void

    @inlinable
    internal init(
        mutateFn: @escaping (AnyMutation<State>) -> Void,
        statePointer: UnsafePointer<State>,
        enableBatchingFn: @escaping () -> Void,
        flushBatchFn: @escaping () -> Void
    ) {
        self.mutateFn = mutateFn
        self.statePointer = statePointer
        self.enableBatchingFn = enableBatchingFn
        self.flushBatchFn = flushBatchFn
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
    public var currentState: State {
        statePointer.pointee
    }

    // MARK: - Mutations

    @inlinable
    public func mutate<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }

    @inlinable
    public func transform<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ modify: (Value) -> Value
    ) {
        let current = statePointer.pointee[keyPath: keyPath]
        mutateFn(.init(keyPath, modify(current)))
    }

    // MARK: - Batching

    @inline(never)
    public func batch(_ build: (borrowing BatchBuilder<State>) -> Void) {
        enableBatchingFn()
        defer { flushBatchFn() }

        let builder = BatchBuilder<State>(
            mutateFn: mutateFn,
            statePointer: statePointer
        )
        build(builder)
    }
}
