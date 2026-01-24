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
     in case a feature's state conforms to the identifiable protocol and andother feature's state's id is the same as the first feature, their ids may collide.
     therefore this initializer is implemented where the objectIdentifier(Feature.swlf) is added in order to make sure the ids across features never collide.
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
