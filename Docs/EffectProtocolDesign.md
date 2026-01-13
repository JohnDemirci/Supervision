# Effect Protocol Design

This document outlines a protocol-oriented approach to redesigning the `Work` type for better testability and cleaner separation of concerns.

## Goals

1. Compile-time type safety for testing
2. No test-only code in production types
3. Simple, focused types (each effect is its own struct)
4. Clean separation of producer and transformer
5. Minimal generic parameters on the main protocol

## Core Protocol

```swift
protocol Effect<Action, Environment, CancellationID> {
    associatedtype Action: Sendable
    associatedtype Environment
    associatedtype CancellationID: Cancellation
}
```

The protocol is minimal. Each concrete effect type adds only what it needs.

## Concrete Effect Types

### Done

Represents no effect. Used when an action only mutates state.

```swift
struct Done<Action: Sendable, Environment, CancellationID: Cancellation>: Effect {
}
```

### Cancel

Cancels a previously started effect by its ID.

```swift
struct Cancel<Action: Sendable, Environment, CancellationID: Cancellation>: Effect {
    let id: CancellationID
}
```

### Run

Executes an async operation and transforms the result to an action.

```swift
struct Run<Action: Sendable, Environment, CancellationID: Cancellation, Value: Sendable>: Effect {
    let priority: TaskPriority?
    let cancellationID: CancellationID?
    let produce: @Sendable (Environment) async throws -> Value
    let transform: @Sendable (Result<Value, Error>) -> Action

    /// Executes the effect (used by Supervisor in production)
    func execute(with env: Environment) async throws -> Action {
        do {
            let value = try await produce(env)
            return transform(.success(value))
        } catch {
            return transform(.failure(error))
        }
    }

    /// Applies transform to a value (used by Tester)
    func receive(value: Value) -> Action {
        transform(.success(value))
    }

    /// Applies transform to an error (used by Tester)
    func receive(error: Error) -> Action {
        transform(.failure(error))
    }
}
```

Note: `receive(value:)` and `receive(error:)` are not test-only methods. They simply expose the transform, which is a natural part of what `Run` does. The Tester uses them, but they could be useful elsewhere too.

### Subscribe

Subscribes to an async sequence and transforms each value to an action.

```swift
struct Subscribe<Action: Sendable, Environment, CancellationID: Cancellation, Value: Sendable>: Effect {
    let cancellationID: CancellationID
    let produce: @Sendable (Environment) async throws -> AsyncThrowingStream<Value, Error>
    let transform: @Sendable (Result<Value, Error>) -> Action

    func receive(value: Value) -> Action {
        transform(.success(value))
    }

    func receive(error: Error) -> Action {
        transform(.failure(error))
    }
}
```

### FireAndForget

Executes an async operation without producing an action.

```swift
struct FireAndForget<Action: Sendable, Environment, CancellationID: Cancellation>: Effect {
    let priority: TaskPriority?
    let work: @Sendable (Environment) async throws -> Void
}
```

## FeatureProtocol

Features return an existential `any Effect`:

```swift
protocol FeatureProtocol {
    associatedtype Action: Sendable
    associatedtype State
    associatedtype Dependency
    associatedtype CancellationID: Cancellation

    init()

    func process(
        action: Action,
        context: borrowing Context<State>
    ) -> any Effect<Action, Dependency, CancellationID>
}
```

## Usage in a Feature

```swift
struct UsersFeature: FeatureProtocol {
    struct State {
        var users: [User] = []
        var isLoading = false
        var error: String?
    }

    enum Action: Sendable {
        case fetchUsers
        case usersResponse(Result<[User], Error>)
        case cancelFetch
    }

    enum CancellationID: Cancellation {
        case fetchUsers
    }

    struct Dependency {
        var api: APIClient
    }

    func process(
        action: Action,
        context: borrowing Context<State>
    ) -> any Effect<Action, Dependency, CancellationID> {
        switch action {
        case .fetchUsers:
            context.state.isLoading = true
            return Run(
                priority: nil,
                cancellationID: .fetchUsers,
                produce: { env in
                    try await env.api.fetchUsers()
                },
                transform: { result in
                    .usersResponse(result)
                }
            )

        case .usersResponse(.success(let users)):
            context.state.isLoading = false
            context.state.users = users
            return Done()

        case .usersResponse(.failure(let error)):
            context.state.isLoading = false
            context.state.error = error.localizedDescription
            return Done()

        case .cancelFetch:
            return Cancel(id: .fetchUsers)
        }
    }
}
```

## Tester

The Tester processes actions and allows type-safe effect completion:

```swift
@MainActor
public final class Tester<Feature: FeatureProtocol> {
    public typealias Action = Feature.Action
    public typealias State = Feature.State
    public typealias Dependency = Feature.Dependency
    public typealias CancellationID = Feature.CancellationID

    private let feature: Feature
    private var _state: State
    private var pending: (any Effect<Action, Dependency, CancellationID>)?

    public init(state: State) {
        self.feature = Feature()
        self._state = state
    }

    public var state: State { _state }

    // MARK: - Send

    @discardableResult
    public func send(_ action: Action) -> EffectAssertion {
        let effect = withUnsafeMutablePointer(to: &_state) { pointer in
            let context = Context<State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                },
                statePointer: UnsafePointer(pointer)
            )
            return feature.process(action: action, context: context)
        }

        self.pending = effect
        return EffectAssertion(effect: effect)
    }

    // MARK: - Receive

    /// Completes a Run effect with a value.
    /// The Value type must match what the Run produces.
    @discardableResult
    public func receive<Value>(value: Value) -> EffectAssertion {
        guard let run = pending as? Run<Action, Dependency, CancellationID, Value> else {
            if let anyRun = pending, type(of: anyRun) is any Run.Type {
                fatalError("Type mismatch: provided \(Value.self) but effect expects a different type")
            }
            fatalError("No pending Run effect. Current: \(type(of: pending))")
        }

        let action = run.receive(value: value)
        pending = nil
        return send(action)
    }

    /// Completes a Run effect with an error.
    public func receive<Value>(
        _: Value.Type,
        error: Error
    ) -> EffectAssertion {
        guard let run = pending as? Run<Action, Dependency, CancellationID, Value> else {
            fatalError("No pending Run effect with value type \(Value.self)")
        }

        let action = run.receive(error: error)
        pending = nil
        return send(action)
    }

    /// Completes a Subscribe effect with a value.
    @discardableResult
    public func receiveSubscription<Value>(value: Value) -> EffectAssertion {
        guard let sub = pending as? Subscribe<Action, Dependency, CancellationID, Value> else {
            fatalError("No pending Subscribe effect with value type \(Value.self)")
        }

        let action = sub.receive(value: value)
        // Don't clear pending - subscription continues
        return send(action)
    }

    /// Directly receive an action (for effects without transformers).
    @discardableResult
    public func receive(action: Action) -> EffectAssertion {
        pending = nil
        return send(action)
    }
}

// MARK: - EffectAssertion

public struct EffectAssertion {
    let effect: any Effect

    public var isDone: Bool {
        effect is Done
    }

    public var isCancel: Bool {
        effect is Cancel
    }

    public var isRun: Bool {
        effect is Run
    }

    public var isSubscribe: Bool {
        effect is Subscribe
    }

    public var isFireAndForget: Bool {
        effect is FireAndForget
    }

    public func assertDone(file: StaticString = #file, line: UInt = #line) {
        guard isDone else {
            fatalError("Expected Done, got \(type(of: effect))", file: file, line: line)
        }
    }

    public func assertCancel<C: Cancellation>(
        id expected: C,
        file: StaticString = #file,
        line: UInt = #line
    ) where C: Equatable {
        guard let cancel = effect as? Cancel<_, _, C>, cancel.id == expected else {
            fatalError("Expected Cancel(\(expected)), got \(type(of: effect))", file: file, line: line)
        }
    }
}
```

## Test Examples

```swift
import Testing

@MainActor
@Suite("UsersFeature Tests")
struct UsersFeatureTests {

    @Test("fetchUsers sets loading and returns Run effect")
    func fetchUsers() {
        let tester = Tester<UsersFeature>(state: .init())

        tester.send(.fetchUsers).assertRun()
        #expect(tester.state.isLoading == true)

        // Complete the effect with a value
        let mockUsers = [User(name: "Alice")]
        tester.receive(value: mockUsers).assertDone()

        #expect(tester.state.isLoading == false)
        #expect(tester.state.users == mockUsers)
    }

    @Test("fetchUsers handles errors")
    func fetchUsersError() {
        let tester = Tester<UsersFeature>(state: .init())

        tester.send(.fetchUsers)

        // Complete with an error
        tester.receive([User].self, error: APIError.offline)

        #expect(tester.state.isLoading == false)
        #expect(tester.state.error != nil)
    }

    @Test("cancelFetch returns Cancel effect")
    func cancelFetch() {
        let tester = Tester<UsersFeature>(state: .init())

        tester.send(.cancelFetch).assertCancel(id: .fetchUsers)
    }

    @Test("type mismatch fails clearly")
    func typeMismatch() {
        let tester = Tester<UsersFeature>(state: .init())

        tester.send(.fetchUsers)

        // This would fail with: "Type mismatch: provided Location but effect expects [User]"
        // tester.receive(value: Location(...))
    }
}
```

## Convenience Extensions (Optional)

To reduce verbosity, add factory methods:

```swift
extension Effect {
    static func done() -> Done<Action, Environment, CancellationID> {
        Done()
    }

    static func cancel(_ id: CancellationID) -> Cancel<Action, Environment, CancellationID> {
        Cancel(id: id)
    }

    static func run<Value: Sendable>(
        priority: TaskPriority? = nil,
        cancellationID: CancellationID? = nil,
        produce: @Sendable @escaping (Environment) async throws -> Value,
        transform: @Sendable @escaping (Result<Value, Error>) -> Action
    ) -> Run<Action, Environment, CancellationID, Value> {
        Run(
            priority: priority,
            cancellationID: cancellationID,
            produce: produce,
            transform: transform
        )
    }
}
```

Note: These extensions won't work directly with existential returns. The explicit struct construction (`Done()`, `Run(...)`) is currently required.

## Comparison with Original Work

| Aspect | Original Work | New Effect Protocol |
|--------|--------------|---------------------|
| Generic params | 3 (Output, Env, CancelID) | 3 on protocol, 4 on Run |
| Value type | Erased in closure | Preserved in Run<..., Value> |
| Test support | Required adding transformer | Natural via receive(value:) |
| Structure | Single enum with cases | Separate structs per effect |
| Type safety | Runtime only | Compile-time for receive |

## Execution Protocols

To execute effects without knowing the `Value` type, we add helper protocols:

```swift
/// Protocol for effects that produce a single action (Run)
protocol RunnableEffect<Action, Environment, CancellationID>: Effect {
    var priority: TaskPriority? { get }
    var cancellationID: CancellationID? { get }
    func execute(with environment: Environment) async throws -> Action
}

/// Protocol for effects that produce multiple actions over time (Subscribe)
protocol SubscribableEffect<Action, Environment, CancellationID>: Effect {
    var cancellationID: CancellationID { get }
    func subscribe(with environment: Environment) async throws -> AsyncThrowingStream<Action, Error>
}
```

### Run Conformance

```swift
extension Run: RunnableEffect {
    func execute(with environment: Environment) async throws -> Action {
        do {
            let value = try await produce(environment)
            return transform(.success(value))
        } catch {
            return transform(.failure(error))
        }
    }
}
```

### Subscribe Conformance

```swift
extension Subscribe: SubscribableEffect {
    func subscribe(with environment: Environment) async throws -> AsyncThrowingStream<Action, Error> {
        let sourceStream = try await produce(environment)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await value in sourceStream {
                        continuation.yield(transform(.success(value)))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(transform(.failure(error)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

## Supervisor Refactoring

The Supervisor changes from switching on `Work.operation` enum cases to type-based dispatch on concrete Effect types.

### Key Changes

1. Stream type: `AsyncStream<Work<...>>` → `AsyncStream<any Effect<...>>`
2. Dispatch: enum switch → type casting with `as`
3. Execution: uses `RunnableEffect` and `SubscribableEffect` protocols

### Refactored Supervisor

```swift
@MainActor
@dynamicMemberLookup
public final class Supervisor<Feature: FeatureProtocol>: Observable {
    public typealias Action = Feature.Action
    public typealias CancellationID = Feature.CancellationID
    public typealias Dependency = Feature.Dependency
    public typealias State = Feature.State

    public let id: ReferenceIdentifier

    let feature: Feature

    private nonisolated let logger: Logger

    // Changed: Stream now carries any Effect
    private let effectContinuation: AsyncStream<any Effect<Action, Dependency, CancellationID>>.Continuation
    private let effectStream: AsyncStream<any Effect<Action, Dependency, CancellationID>>
    private let dependency: Dependency

    private let observationMap: Feature.ObservationMap
    private let worker: Worker<Action, Dependency, CancellationID>
    private var processingTask: Task<Void, Never>?
    private var _observationTokens: [PartialKeyPath<State>: ObservationToken] = [:]
    private var _state: State

    // MARK: - Initialization

    init(
        id: ReferenceIdentifier,
        state: State,
        dependency: Dependency
    ) {
        self.dependency = dependency
        self.worker = Worker()
        self.feature = Feature()
        self.id = id
        self.logger = .init(subsystem: "com.Supervision.\(Feature.self)", category: "Supervisor")
        self._state = state

        // Changed: Stream type
        let (stream, continuation) = AsyncStream.makeStream(
            of: (any Effect<Action, Dependency, CancellationID>).self,
            bufferingPolicy: .unbounded
        )

        self.observationMap = feature.observationMap.reduce(
            into: Feature.ObservationMap()
        ) { partialResult, kvp in
            kvp.value.forEach { valueKeypath in
                partialResult[valueKeypath, default: []].append(kvp.key)
            }
        }

        self.effectStream = stream
        self.effectContinuation = continuation

        self.processingTask = Task { [weak self] in
            for await effect in stream {
                guard let self else { return }
                await self.processEffect(effect)
            }
        }
    }

    isolated deinit {
        effectContinuation.finish()
        processingTask?.cancel()
        processingTask = nil
    }

    public subscript<Subject>(dynamicMember keyPath: KeyPath<State, Subject>) -> Subject {
        trackAccess(for: keyPath)
        return _state[keyPath: keyPath]
    }
}
```

### Action Dispatch

```swift
extension Supervisor {
    public func send(_ action: Action) {
        let effect: any Effect<Action, Dependency, CancellationID> = withUnsafeMutablePointer(
            to: &_state
        ) { [self] pointer in
            let context = Context<Feature.State>(
                mutateFn: { @MainActor mutation in
                    mutation.apply(&pointer.pointee)
                    self.notifyChange(for: mutation.keyPath)
                },
                statePointer: UnsafePointer(pointer)
            )

            return self.feature.process(action: action, context: context)
        }

        // Type-based dispatch instead of enum switch
        switch effect {
        case is Done<Action, Dependency, CancellationID>:
            return

        case let cancel as Cancel<Action, Dependency, CancellationID>:
            Task { await self.worker.cancel(taskID: cancel.id) }

        default:
            // Run, Subscribe, FireAndForget go to the stream
            effectContinuation.yield(effect)
        }
    }

    private func processEffect(_ effect: any Effect<Action, Dependency, CancellationID>) async {
        switch effect {
        case is Done<Action, Dependency, CancellationID>:
            return

        case let cancel as Cancel<Action, Dependency, CancellationID>:
            await self.worker.cancel(taskID: cancel.id)

        case let fireAndForget as FireAndForget<Action, Dependency, CancellationID>:
            Task {
                await worker.runFireAndForget(fireAndForget, using: dependency)
            }

        case let run as any RunnableEffect<Action, Dependency, CancellationID>:
            let resultAction = await self.worker.run(run, using: self.dependency)
            if let resultAction {
                self.send(resultAction)
            }

        case let subscribe as any SubscribableEffect<Action, Dependency, CancellationID>:
            await self.worker.runSubscription(
                subscribe,
                using: self.dependency,
                onAction: { [weak self] action in
                    self?.send(action)
                }
            )

        default:
            logger.warning("Unknown effect type: \(type(of: effect))")
        }
    }
}
```

## Worker Refactoring

The Worker actor is updated to work with the new protocols:

```swift
actor Worker<Action: Sendable, Dependency, CancellationID: Cancellation> {
    private var runningTasks: [CancellationID: Task<Void, Never>] = [:]

    func cancel(taskID: CancellationID) {
        runningTasks[taskID]?.cancel()
        runningTasks.removeValue(forKey: taskID)
    }

    func run(
        _ effect: any RunnableEffect<Action, Dependency, CancellationID>,
        using dependency: Dependency
    ) async -> Action? {
        // Check for duplicate cancellation ID
        if let id = effect.cancellationID, runningTasks[id] != nil {
            // Already running, skip
            return nil
        }

        // Track the task if it has a cancellation ID
        if let id = effect.cancellationID {
            let task = Task {
                // Task body handled below
            }
            runningTasks[id] = task
        }

        do {
            let action = try await effect.execute(with: dependency)

            if let id = effect.cancellationID {
                runningTasks.removeValue(forKey: id)
            }

            return action
        } catch is CancellationError {
            return nil
        } catch {
            // Log error, return nil (no action produced)
            return nil
        }
    }

    func runFireAndForget(
        _ effect: FireAndForget<Action, Dependency, CancellationID>,
        using dependency: Dependency
    ) async {
        do {
            try await effect.work(dependency)
        } catch {
            // Log error silently
        }
    }

    func runSubscription(
        _ effect: any SubscribableEffect<Action, Dependency, CancellationID>,
        using dependency: Dependency,
        onAction: @escaping @MainActor (Action) -> Void
    ) async {
        let id = effect.cancellationID

        // Check for duplicate
        if runningTasks[id] != nil {
            return
        }

        let task = Task {
            do {
                let stream = try await effect.subscribe(with: dependency)
                for try await action in stream {
                    await onAction(action)
                }
            } catch is CancellationError {
                // Normal cancellation
            } catch {
                // Log error
            }
        }

        runningTasks[id] = task

        // Wait for completion
        await task.value
        runningTasks.removeValue(forKey: id)
    }
}
```

## Migration Path

1. Create new Effect protocol and concrete types
2. Create RunnableEffect and SubscribableEffect protocols
3. Update FeatureProtocol to return `any Effect`
4. Update Supervisor to handle each effect type
5. Update Worker to use the new protocols
6. Update Tester to use typed receive
7. Deprecate old Work type
8. Migrate features one at a time

## Open Questions

1. Should we add convenience factories even if they require explicit type annotation?
2. How to handle the `onError` fallback that Work currently supports?
3. Should FireAndForget have a cancellation ID?
4. Naming: `Run` vs `Task` vs `AsyncTask`?
