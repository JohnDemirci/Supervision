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

    public func set<Value: Equatable>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        let oldValue = statePointer.pointee[keyPath: keyPath]
        guard oldValue != newValue else { return }
        mutateFn(.init(keyPath, newValue))
    }

    public func set<Value>(_ keyPath: WritableKeyPath<State, Value>, to newValue: Value) {
        mutateFn(.init(keyPath, newValue))
    }
}
