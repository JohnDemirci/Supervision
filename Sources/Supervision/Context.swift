//
//  Context.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

/// A non-copyable non-escapable value type that encapsulates the current state of a feature,
/// enabling controlled reads and mutations.
///
/// ```swift
/// func process(action: Action, context: borrowing Context<State>) -> FeatureWork
/// ```
/// You do not typically create a `Context`; it is provided by ``Feature`` when `process` is called.
@dynamicMemberLookup
public struct Context<State>: ~Copyable, ~Escapable {
    @usableFromInline
    internal let statePointer: UnsafeMutablePointer<State>

    @_lifetime(borrow statePointer)
    internal init(statePointer: UnsafeMutablePointer<State>) {
        self.statePointer = statePointer
    }

    @inlinable
    @inline(__always)
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<State, Value>) -> Value {
        _read {
            yield state[keyPath: keyPath]
        }
        nonmutating _modify {
            yield &state[keyPath: keyPath]
        }
    }

    @inlinable
    @inline(__always)
    public var state: State {
        _read {
            yield statePointer.pointee
        }
        nonmutating _modify {
            yield &statePointer.pointee
        }
    }
}
