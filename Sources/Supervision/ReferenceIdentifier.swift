//
//  ReferenceIdentifier.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

public final class ReferenceIdentifier: Identifiable, Hashable, @unchecked Sendable {
    public let id: AnyHashable

    init(id: AnyHashable) {
        self.id = id
    }

    public static func == (lhs: ReferenceIdentifier, rhs: ReferenceIdentifier) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
