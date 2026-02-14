//
//  ReferenceIdentifier.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

public final class ReferenceIdentifier: Identifiable, Hashable, @unchecked Sendable {
    /// The underlying identifier value.
    ///
    /// This can be any `Hashable` value:
    /// - For `Identifiable` state: The state's `id` property
    /// - For non-identifiable state: An `ObjectIdentifier` of the supervisor type
    public let id: AnyHashable

    init(id: AnyHashable) {
        self.id = id
    }
    
    /*
     In case a feature's state conforms to Identifiable and another feature's state has the same id,
     their identifiers may collide. This initializer includes the feature type identifier to avoid
     collisions across feature types.
     */
    init(_ ids: AnyHashable...) {
        precondition(!ids.isEmpty, "ReferenceIdentifier requires at least one ID")
        self.id = AnyHashable(ids)
    }

    public static func == (lhs: ReferenceIdentifier, rhs: ReferenceIdentifier) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
