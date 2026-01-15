//
//  FeatureProtocol.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Foundation

/// A protocol that defines a self-contained feature with state, actions, and side effects.
///
/// `FeatureProtocol` is the core building block of the Supervision architecture. Each feature
/// encapsulates its own state, the actions that can modify it, and the side effects those
/// actions can trigger.
///
/// ## Overview
///
/// Implement this protocol to define a feature in your application:
///
/// ```swift
/// struct CounterFeature: FeatureProtocol {
///     struct State {
///         var count = 0
///         var isLoading = false
///     }
///
///     enum Action {
///         case increment
///         case decrement
///         case fetchCount
///         case countLoaded(Int)
///     }
///
///     typealias Dependency = APIClient
///
///     func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
///         switch action {
///         case .increment:
///             context.state.count += 1
///             return .empty()
///
///         case .decrement:
///             context.state.count -= 1
///             return .empty()
///
///         case .fetchCount:
///             context.state.isLoading = true
///             return .run { api in
///                 let count = try await api.fetchCount()
///                 return .countLoaded(count)
///             }
///
///         case .countLoaded(let count):
///             context.state.count = count
///             context.state.isLoading = false
///             return .empty()
///         }
///     }
/// }
/// ```
///
/// ## State
///
/// State should be a value type (struct or enum) containing all data the feature needs:
///
/// ```swift
/// struct State {
///     var items: [Item] = []
///     var selectedID: Item.ID?
///     var isLoading = false
///     var error: String?
/// }
/// ```
///
/// ## Actions
///
/// Actions represent all possible events in your feature—user interactions, delegate callbacks,
/// and responses from side effects:
///
/// ```swift
/// enum Action {
///     // User actions
///     case addButtonTapped
///     case itemSelected(Item.ID)
///
///     // Side effect responses
///     case itemsLoaded(Result<[Item], Error>)
/// }
/// ```
///
/// ## Dependencies
///
/// Dependencies provide access to external services for side effects:
///
/// ```swift
/// struct Dependency {
///     var apiClient: APIClient
///     var database: Database
///     var analytics: Analytics
/// }
/// ```
///
/// Use `Void` when your feature has no dependencies:
///
/// ```swift
/// typealias Dependency = Void
/// ```
///
/// ## Processing Actions
///
/// The ``process(action:context:)`` method is where you implement your feature's logic.
/// It receives an action and a context for mutating state, and returns ``Work``
/// describing any side effects to execute.
///
/// ## Thread Safety
///
/// `FeatureProtocol` is `@MainActor` isolated. All state mutations and action
/// processing occur on the main thread.
@MainActor
public protocol FeatureProtocol {
    typealias FeatureWork = Work<Action, Dependency>

    typealias ObservationMap = [PartialKeyPath<State>: [PartialKeyPath<State>]]

    associatedtype State: Equatable

    var observationMap: ObservationMap { get }

    associatedtype Action: Sendable

    associatedtype Dependency: Sendable

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork

    init()
}

extension FeatureProtocol {
    public var observationMap: ObservationMap {
        [:]
    }
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
