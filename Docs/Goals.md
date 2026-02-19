# Supervision Goals

This document captures the goals for the Supervision library, explains how the current codebase aligns to them, and provides focused code samples for each goal.

## Core Principles

- Value-type state with granular observation.
- Controlled state mutation via a single `process` entrypoint.
- Async work is modeled explicitly and can be cancelled, throttled, debounced, merged, or concatenated.
- Feature instances are reusable and identity-based across modules.
- Testing is first-class and does not require dependency mocking.

## Goal 1: Lightweight state management with focused building blocks

**Goal**
Create a lightweight state management architecture that streamlines common processes such as fetching data, canceling network requests, and observation.

**Alignment in code**
- `FeatureBlueprint` defines the feature boundary (State, Action, Dependency, and `process`).
- `Feature` is the runtime owner of state and observation tokens.
- `Context` provides safe, zero-copy reads and controlled mutations.
- `Work` models side effects (run, cancel, merge, concatenate).
- `Worker` executes Work and handles cancellations, debounce, and throttle.

**Example**
```swift
struct TodosFeature: FeatureBlueprint {
    struct State: Equatable {
        var todos: [String] = []
        var isLoading = false
    }

    enum Action: Sendable {
        case refresh
        case response([String])
        case failed(Error)
    }

    struct Dependency: Sendable {
        var fetch: @Sendable () async throws -> [String]
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .refresh:
            context.modify(\.isLoading, to: true)
            return .run { env in
                try await env.fetch()
            } map: { result in
                switch result {
                case .success(let todos):
                    return .response(todos)
                case .failure(let error):
                    return .failed(error)
                }
            }
            .cancellable(id: "todos.fetch", cancelInFlight: true)

        case .response(let todos):
            context.modify { batch in
                batch.set(\.todos, to: todos)
                batch.set(\.isLoading, to: false)
            }
            return .done

        case .failed:
            context.modify(\.isLoading, to: false)
            return .done
        }
    }
}
```

## Goal 2: Granular observation with chained key paths

**Goal**
Create an observation mechanism where changes to value-type properties are notified precisely. It should work with chained key paths (e.g. `\.some.nested.value`) and notify only views that observe the affected data. Apple's Observation framework targets reference types, and other libraries lean on Swift macros via SwiftSyntax. Supervision handles this without macros.

**Alignment in code**
- `Feature` stores per-keypath `ObservationToken`s to drive granular updates.
- `Feature.read(_:)` and `Feature[subscript:]` track reads for any key path, including nested ones.
- `Context.modify` only triggers notifications when values actually change (Equatable fast path).
- `FeatureBlueprint.observationMap` lets you declare computed-property dependencies.

**Example: chained key path reads**
```swift
struct ProfileFeature: FeatureBlueprint {
    struct State: Equatable {
        var user = User()
        struct User: Equatable { var name = ""; var age = 0 }
    }
    enum Action: Sendable { case setName(String) }
    typealias Dependency = Void

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        if case .setName(let name) = action {
            context.modify(\.user.name, to: name)
        }
        return .done
    }
}

let feature = Feature<ProfileFeature>(state: .init(), dependency: ())
let name = feature[\.user.name] // Tracks nested key path
```

**Example: scoped key path reads with parent tracking**
```swift
let feature = Feature<ProfileFeature>(state: .init(), dependency: ())
let name = feature
    .scope(\.user)
    .value(\.name)
// Deeper nesting can use multi-arg overloads:
// let value = feature.scope(\.parent1, \.parent2, \.parent3).value(\.child)
```

**Example: key path reads without parent tracking**
```swift
let feature = Feature<ProfileFeature>(state: .init(), dependency: ())
let name = feature[\.user.name]
```

**Example: computed-property dependencies**
```swift
struct NameFeature: FeatureBlueprint {
    @ObservableValue
    struct State: Equatable {
        var first = ""
        var last = ""
        var full: String { "\(first) \(last)" }
    }

    enum Action: Sendable { case setFirst(String) }
    typealias Dependency = Void

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        if case .setFirst(let first) = action {
            context.modify(\.first, to: first)
        }
        return .done
    }
}
```

## Goal 3: Zero-copy reads when interacting with Context

**Goal**
Zero-copy reads on state when interacting with `Context`.

**Alignment in code**
- `Context.state` uses `_read` and an unsafe pointer to yield state without copying.
- `Context` is `~Copyable`, so it cannot escape the `process` scope.

**Example**
```swift
func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
    let count = context.state.count // zero-copy read
    if count > 10 { /* ... */ }
    return .done
}
```

## Goal 4: Controlled state mutation via `process`

**Goal**
State mutations only happen in a controlled environment (the `process` function, through `Context`).

**Alignment in code**
- `Feature` keeps `_state` private and exposes mutation only through `Context.modify`.
- `Context.modify` supports equatable checks to prevent no-op writes.
- SwiftUI `directBinding` is an explicit opt-in escape hatch for UI-only state.

**Example**
```swift
func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
    switch action {
    case .increment:
        context.modify(\.count) { $0 += 1 }
        return .done
    case .setName(let name):
        context.modify(\.name, to: name.trimmingCharacters(in: .whitespaces))
        return .done
    }
}
```

## Goal 5: Reuse Feature instances across modules with automatic lifecycle

**Goal**
Multi-module applications can reuse existing features in memory. The lifecycle of `Feature` objects is handled by `FeatureContainer`, where objects are weakly held and automatically deallocated.

**Alignment in code**
- `FeatureContainer` uses `NSMapTable` with weak references.
- Repeated requests for the same ID return the same instance, if still alive.

**Example**
```swift
struct AppDependency {
    let api: API
}

let container = FeatureContainer(dependency: AppDependency(api: .live))
let todos = container.feature(state: TodosFeature.State()) { $0.api }
```

## Goal 6: Stable feature identity for reuse

**Goal**
Feature objects are identifiable. If `State` is `Identifiable`, the identity is `Feature.self + state.id`. If not, identity is `Feature.self`.

**Alignment in code**
- `ReferenceIdentifier` composes state ID with feature type to avoid collisions.
- `Feature.makeID(from:)` and `Feature` initializers enforce the identity rules.

**Example**
```swift
struct UserFeature: FeatureBlueprint {
    struct State: Identifiable, Equatable { let id: UUID; var name: String }
    enum Action: Sendable { case rename(String) }
    typealias Dependency = Void

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork { .done }
}

let user = Feature<UserFeature>(state: .init(id: UUID(), name: "A"), dependency: ())
let id = user.id // combines UserFeature.self + state.id
```

## Goal 7: Testing harness without dependency mocking

**Goal**
Provide a test harness so consumers only need to provide values for async `Work` operations (no dependency mocks).

**Alignment in code**
- `Tester` runs feature logic with an in-memory state.
- `WorkInspection` lets tests assert the kind of work and feed results back in.
- `Work` includes a `TestPlan` in DEBUG/test runs for tasks and streams.

**Example**
```swift
let tester = Tester<TodosFeature>(state: .init())

let inspection = tester.send(.refresh) { state in
    #expect(state.isLoading == true)
}

// Assert the Work and feed a simulated result
inspection.assertRun()
let next = try tester.feedResult(for: inspection, result: .success(["A", "B"])) { state in
    #expect(state.todos == ["A", "B"])
    #expect(state.isLoading == false)
}

// Continue with the resulting action if needed
_ = tester.send(next)
```

## Goal 8: Preview helpers (TBD)

**Goal**
Provide a preview helper for `Feature` objects to simplify SwiftUI previews.

**Current status**
Planned but not implemented yet.

## Appendix: Work patterns for cancellation & coordination

**Cancellation and throttling**
```swift
return .run { env in
    try await env.fetch()
} map: { .response($0) }
.cancellable(id: "fetch", cancelInFlight: true)
.throttle(for: .seconds(1))
```

**Merging or concatenating work**
```swift
return .merge(
    .run { env in try await env.fetchA() } map: { .a($0) },
    .run { env in try await env.fetchB() } map: { .b($0) }
)

return .concatenate(
    .run { env in try await env.step1() } map: { .step1($0) },
    .run { env in try await env.step2() } map: { .step2($0) }
)
```
