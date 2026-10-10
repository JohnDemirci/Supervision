//
//  FeatureBlueprint.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import ValueObservation

/// Defines the state, actions, dependencies, and behavior of a Supervision feature.
///
/// A conforming type models one unit of application logic. Its observable `State` is the
/// source of truth, `Action` describes every input it accepts, and `Dependency` contains
/// the external services needed by asynchronous work.
///
/// ``process(action:context:featureID:)`` performs immediate state mutations through a
/// borrowed ``Context`` and returns ``Work`` describing any follow-up effects. The
/// `featureID` identifies the live feature instance processing the action.
///
/// Associated types:
/// - `State`: An `ObservableValue`, normally an `@ObservableValue` structure.
/// - `Action`: The `Sendable` inputs handled by the feature.
/// - `Dependency`: The `Sendable` services available to work returned by the feature.
///
/// `FeatureWork` is a convenience typealias for `Work<Action, Dependency>`.
///
/// ## Example ##
/// ```swift
/// struct ProfileFeature: FeatureBlueprint {
///     @ObservableValue
///     struct State {
///         var firstName = ""
///         var lastName = ""
///     }
///
///     enum Action: Sendable {
///         case setFirstName(String)
///         case setLastName(String)
///     }
///
///     typealias Dependency = Void
///
///     func process(
///         action: Action,
///         context: borrowing Context<State>,
///         featureID: ReferenceIdentifier
///     ) -> FeatureWork {
///         switch action {
///         case .setFirstName(let name):
///             context.firstName = name
///         case .setLastName(let name):
///             context.lastName = name
///         }
///
///         return .done
///     }
/// }
/// ```
///
/// See also:
/// - ``Work`` for describing mutations and effects
/// - ``Context`` for state access and scoping
public protocol FeatureBlueprint: Sendable {
    typealias FeatureWork = Work<Action, Dependency>

    /// Source of truth for the Feature's state
    associatedtype State: ObservableValue

    associatedtype Event: Sendable = Void

    /// Actions that are dispatched, or a result of users' interactions
    associatedtype Action: Sendable

    /// Typically a struct that contains all the dependencies such as RESTClient to perform work.
    associatedtype Dependency: Sendable

    /// Processes dispatched actions and returns an instance of ``Work``
    ///
    /// - Parameters:
    ///    - action: The dispatched ``Action``
    ///    - context: The context of the ``State``
    ///
    /// - Returns: ``Work`` to be performed.
    func process(
        action: Action,
        context: borrowing Context<State>,
        featureID: ReferenceIdentifier
    ) -> FeatureWork

    init()
}
