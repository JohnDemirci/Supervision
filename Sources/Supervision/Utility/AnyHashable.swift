//
//  AnyHashable.swift
//  Supervision
//
//  Created by John Demirci on 1/12/26.
//

import Foundation

public struct AnyHashableSendable: Hashable, Sendable {
    public let value: any (Hashable & Sendable)

    public init(value: some (Hashable & Sendable)) {
        if let value = value as? AnyHashableSendable {
            self = value
        } else {
            self.value = value
        }
    }

    @_disfavoredOverload
    public init(value: any (Hashable & Sendable)) {
        if let value = value as? AnyHashableSendable {
            self = value
        } else {
            self.value = value
        }
    }
}

extension AnyHashableSendable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(value))
    }
}

extension AnyHashableSendable: CustomStringConvertible {
    public var description: String {
        String(describing: value)
    }
}

extension AnyHashableSendable: _HasCustomAnyHashableRepresentation {
    public func _toCustomAnyHashable() -> AnyHashable? {
        value as? AnyHashable
    }
}
