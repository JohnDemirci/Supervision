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
    /// The state managed by this feature.
    ///
    /// State should be a value type (struct or enum) to ensure predictable behavior.
    /// Using a reference type (class) will trigger a runtime warning.
    ///
    /// ```swift
    /// struct State {
    ///     var userName: String = ""
    ///     var isLoggedIn: Bool = false
    /// }
    /// ```
    associatedtype State: Equatable

    /// The actions that can be dispatched to this feature.
    ///
    /// Actions represent events that can occur—user interactions, timer ticks,
    /// network responses, etc. Define as an enum with associated values:
    ///
    /// ```swift
    /// enum Action {
    ///     case loginTapped
    ///     case usernameChanged(String)
    ///     case loginResponse(Result<User, Error>)
    /// }
    /// ```
    ///
    /// Actions must be `Sendable` to safely cross actor boundaries.
    associatedtype Action: Sendable

    /// The dependencies required to execute side effects.
    ///
    /// Inject API clients, databases, and other services your feature needs:
    ///
    /// ```swift
    /// struct Dependency {
    ///     var apiClient: APIClient
    ///     var userDefaults: UserDefaults
    /// }
    /// ```
    ///
    /// Use `Void` for features with no external dependencies:
    ///
    /// ```swift
    /// typealias Dependency = Void
    /// ```
    ///
    /// Dependencies must be `Sendable` to safely pass to async work.
    associatedtype Dependency: Sendable

    /// Processes an action and returns any resulting side effects.
    ///
    /// This is the core of your feature's logic. For each action:
    /// 1. Mutate state via `context.state`
    /// 2. Return ``Work`` describing side effects (or `.empty()` for none)
    ///
    /// ```swift
    /// func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
    ///     switch action {
    ///     case .increment:
    ///         context.state.count += 1
    ///         return .empty()
    ///
    ///     case .fetchData:
    ///         return .run { env in
    ///             let data = try await env.api.fetch()
    ///             return .dataLoaded(data)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - action: The action to process.
    ///   - context: A borrowed context providing access to state mutation.
    /// - Returns: Work describing side effects, or `.empty()` for no effects.
    ///
    /// - Note: The context is `borrowing` to prevent escaping. State mutations
    ///   are synchronous and complete before this method returns.
    func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency>

    /// Creates a new instance of the feature.
    ///
    /// The Supervisor creates a feature instance internally. Your feature
    /// should not require any parameters for initialization:
    ///
    /// ```swift
    /// struct MyFeature: FeatureProtocol {
    ///     // No stored properties needed - state is managed by Supervisor
    ///     init() {}
    /// }
    /// ```
    ///
    /// If your feature needs configuration, pass it through the `Dependency` type instead.
    init()
}

/// Type-erased mutation that can be applied to state.
/// Includes the keyPath for granular observation tracking.
@usableFromInline
struct AnyMutation<State> {
    /// The type-erased keyPath that this mutation affects.
    /// Used by Supervisor to notify only observers of this specific property.
    @usableFromInline
    let keyPath: AnyKeyPath

    /// The closure that applies the mutation to the state.
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
