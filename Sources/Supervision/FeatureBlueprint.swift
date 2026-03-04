//
//  FeatureBlueprint.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation
import ValueObservation

/// A blueprint protocol that defines the core requirements for a feature in the Supervision architecture.
///
/// Conforming types model a unit of application logic with a source-of-truth `State`,
/// a set of `Action`s that can be dispatched (typically from user interactions or side effects),
/// and a `Dependency` container that provides external services (e.g., networking, persistence).
///
/// A feature processes actions into work via `process(action:context:)`, producing a `Work` value
/// that can mutate state and/or trigger effects. Features can also declare an `observationMap` to
/// describe dependencies between stored properties and derived (computed) properties, enabling
/// efficient observation for value types without macros.
///
/// Typealiases:
/// - `FeatureWork`: A `Work<Action, Dependency>` describing the operations to perform as a result of processing an action.
/// - `ObservationMap`: A mapping from a computed `PartialKeyPath<State>` to the stored `PartialKeyPath<State>` keys that affect it.
///
/// Associated Types:
/// - `State`: The source-of-truth value type for the feature. Must conform to `Equatable`.
/// - `Action`: The set of actions that drive the feature. Must conform to `Sendable`.
/// - `Dependency`: A container of external dependencies used by the feature. Must conform to `Sendable`.
///
/// ## Example ##
/// ```swift
/// struct ProfileFeature: FeatureBlueprint {
///     struct State: Equatable {
///         var firstName = ""
///         var lastName = ""
///         var fullName: String { "\(firstName) \(lastName)" }
///     }
///
///     enum Action: Sendable {
///         case setFirstName(String)
///         case setLastName(String)
///     }
///
///     struct Dependency: Sendable {
///         let analytics: AnalyticsClient
///     }
///
///     var observationMap: ObservationMap {
///         [\State.fullName: [\State.firstName, \State.lastName]]
///     }
///
///     func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
///         switch action {
///         case .setFirstName(let name):
///             context.modify(\.firstName, to: name)
///             return .done
///         case .setLastName(let name):
///             context.modify(\.lastName, to: name)
///             return .done
///         }
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
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork

    init()
}

@usableFromInline
struct AnyMutation<State> {
    @usableFromInline
    let keyPath: PartialKeyPath<State>

    @usableFromInline
    var apply: (inout State) -> Void

    @usableFromInline
    init<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        _ value: Value
    ) {
        self.keyPath = keyPath
        self.apply = { state in
            state[keyPath: keyPath] = value
        }
    }
}
