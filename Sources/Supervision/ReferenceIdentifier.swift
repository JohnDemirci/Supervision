//
//  ReferenceIdentifier.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

/// A reference-based identifier used to uniquely identify supervisors.
///
/// `ReferenceIdentifier` wraps any `Hashable` value and provides reference semantics
/// for use with `NSMapTable`. This enables ``Board`` to use weak references for
/// automatic supervisor cleanup.
///
/// ## Overview
///
/// ReferenceIdentifier is used internally by ``Supervisor`` and ``Board`` to manage
/// supervisor identity and caching:
///
/// - For `Identifiable` state: ID is derived from `state.id`
/// - For non-identifiable state: ID is based on the feature's type
///
/// ## Why Reference Type?
///
/// `NSMapTable` requires reference types for weak key storage. ReferenceIdentifier
/// provides this while maintaining value-based equality through its wrapped `id`.
///
/// ## Thread Safety
///
/// This class is marked `@unchecked Sendable` because it is immutable—the `id`
/// property is `let` and `AnyHashable` is value-typed. Once initialized, the
/// instance cannot be modified, making it safe to share across actor boundaries.
///
/// ## Usage
///
/// You typically don't create `ReferenceIdentifier` directly. Access it through
/// a supervisor:
///
/// ```swift
/// let supervisor = Supervisor<MyFeature>(state: .init(), dependency: ())
/// print(supervisor.id)  // ReferenceIdentifier
/// ```
public final class ReferenceIdentifier: Identifiable, Hashable, @unchecked Sendable {
    /// The underlying identifier value.
    ///
    /// This can be any `Hashable` value:
    /// - For `Identifiable` state: The state's `id` property
    /// - For non-identifiable state: An `ObjectIdentifier` of the supervisor type
    public let id: AnyHashable

    /// Creates a reference identifier with the given hashable value.
    ///
    /// - Parameter id: Any hashable value to use as the identifier.
    init(id: AnyHashable) {
        self.id = id
    }

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
