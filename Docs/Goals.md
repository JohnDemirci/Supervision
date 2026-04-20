# Supervision Goals

This document captures the goals of the Supervision library and maps each goal to what is implemented today.

## Core Principles

- Feature logic is modeled through `FeatureBlueprint` (`State`, `Action`, `Dependency`, and `process`).
- State is value-based and observable (`State: Equatable & ObservableValue`).
- State mutations happen through `Context`, with `Feature` as source-of-truth owner.
- Side effects are explicit through `Work` and executed by `Worker`.
- Feature identity is stable and supports reuse via `FeatureContainer`.
- Testing is built into the architecture via `Tester` and `WorkInspection`.

## Goal 1: Lightweight feature model

**Goal**
Provide a small, explicit architecture for state, actions, dependencies, and effectful work.

**Alignment in code**
- `FeatureBlueprint` defines the boundary for each feature.
- `Feature.send(_:)` is the action entrypoint.
- `Context` is passed to `process(action:context:)` for reads and writes.
- `Work<Action, Dependency>` is the return type for follow-up work.

**Example**
```swift
import Supervision
import ValueObservation

struct TodosFeature: FeatureBlueprint {
    @ObservableValue
    struct State: Equatable {
        var todos: [String] = []
        var isLoading = false
    }

    enum Action: Sendable {
        case refresh
        case response(Result<[String], Error>)
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
            } map: { .response($0) }
            .cancellable(id: "todos.fetch", cancelInFlight: true)

        case .response(.success(let todos)):
            context.modify { batch in
                batch.set(\.todos, to: todos)
                batch.set(\.isLoading, to: false)
            }
            return .done

        case .response(.failure):
            context.modify(\.isLoading, to: false)
            return .done
        }
    }
}
```

## Goal 2: Value-type observation with granular updates

**Goal**
Support observation for value-type state and nested properties without forcing store-wide invalidation.

**Alignment in code**
- `FeatureBlueprint.State` must conform to `ObservableValue`.
- `Feature` exposes state reads (`state` and dynamic member lookup).
- `Shared` provides a focused, observable projection for a key path (with optional mapping).

**Example**
```swift
import Supervision
import ValueObservation

struct ProfileFeature: FeatureBlueprint {
    @ObservableValue
    struct State: Equatable {
        var user = User()
        struct User: Equatable { var name = "" }
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

let feature = Feature<ProfileFeature>(state: .init())
let sharedName = Shared(feature: feature, keypath: \.user.name)
let currentName = sharedName.value
```

## Goal 3: Zero-copy reads and controlled mutation via `Context`

**Goal**
Make state reads efficient and keep writes constrained to feature processing.

**Alignment in code**
- `Context` is `~Copyable`, so it cannot be copied or escaped from `process`.
- `Context.state` uses `_read` and an internal pointer to avoid unnecessary copies.
- `Context.modify` has `Equatable`-optimized and unconditional overloads.
- `BatchBuilder` supports grouped mutations.

**Example**
```swift
func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
    if context.state.count > 100 {
        context.modify(\.isOverLimit, to: true)
    }

    context.modify { batch in
        batch.set(\.lastUpdatedAt, to: .now)
        batch.set(\.count, to: context.state.count + 1)
    }

    return .done
}
```

## Goal 4: Explicit async work and lifecycle control

**Goal**
Represent side effects explicitly and support cancellation, throttling, debouncing, and composition.

**Alignment in code**
- `Work.Operation` supports `.done`, `.cancel`, `.run`, `.merge`, `.concatenate`.
- `Work` provides `.run`, `.subscribe`, `.fireAndForget`, `.send`.
- `Work` modifiers: `.named`, `.cancellable`, `.priority`, `.throttle`, `.debounce`, `.map`.
- `Worker` handles in-flight tracking, cancellation IDs, throttle timestamps, and async execution.
- `Feature.send(_:)` executes `.cancel` work immediately; other work is queued through `AsyncStream`.
- `merge` and `concatenate` accept up to 5 non-empty works.

**Example**
```swift
return .run { env in
    try await env.fetch()
} map: { .response($0) }
.cancellable(id: "fetch", cancelInFlight: true)
.debounce(for: .milliseconds(250))
.throttle(for: .seconds(1))
```

```swift
return .merge(
    .run { env in try await env.fetchA() } map: { .loadedA($0) },
    .run { env in try await env.fetchB() } map: { .loadedB($0) }
)
```

```swift
return .concatenate(
    .send(.step1Started),
    .run { env in try await env.step1() } map: { .step1Finished($0) },
    .run { env in try await env.step2() } map: { .step2Finished($0) }
)
```

## Goal 5: Stable identity and reusable feature instances

**Goal**
Keep feature identity stable and enable reuse of live feature instances across modules.

**Alignment in code**
- `ReferenceIdentifier` is used as the feature identity key.
- `Feature.makeID(from:)` combines `state.id` with feature type for identifiable states.
- `Feature.makeID()` scopes identity to feature type for non-identifiable states.
- `FeatureContainer` caches features in a weak-to-weak `NSMapTable`.

**Example**
```swift
import Supervision
import ValueObservation

struct InboxFeature: FeatureBlueprint {
    @ObservableValue
    struct State: Identifiable, Equatable {
        let id: String
        var title = ""
    }

    enum Action: Sendable { case noop }
    typealias Dependency = String

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        .done
    }
}

struct AppDependency {
    let userID: String
}

let container = FeatureContainer(dependency: AppDependency(userID: "u1"))
let featureA = container.feature(state: InboxFeature.State(id: "inbox")) { $0.userID }
let featureB = container.feature(state: InboxFeature.State(id: "inbox")) { $0.userID }

// Same identity, same cached instance while retained.
let sameInstance = featureA === featureB
```

## Goal 6: SwiftUI bindings with explicit trade-offs

**Goal**
Support both architecture-first bindings and high-performance direct bindings.

## Goal 7: Compose live features into derived state

**Goal**
Support lightweight composition of existing live features into a derived, observable feature without introducing a new parent reducer/store.

**Alignment in code**
- `Composed.of(...)` accepts one or more existing `Feature` instances using variadic generics.
- `ComposedBlueprint` defines how child states map into a derived `State` and how composed actions fan out into optional child actions.
- `ComposedBuilder.composedBy(...)` supports both an explicit `ComposedBlueprint` and closure-based convenience overload.
- `ComposedFeature` forwards actions to children and derives its `state` from current child states.

**How to use**
1. Create or obtain the child `Feature` instances you want to compose.
2. Define a composed `Action` and derived `State` for the UI boundary.
3. Call `Composed.of(...)` with child features.
4. Provide `send` mapping from composed action to optional child actions.
5. Provide `mapValue` mapping from child states to derived state.

**Example**
```swift
let dashboard = Composed.of(profileFeature, settingsFeature).composedBy(
    send: { (action: DashboardAction) in
        switch action {
        case .refresh:
            (.reload, .fetchPreferences)
        case .toggleNotifications(let enabled):
            (nil, .setNotificationsEnabled(enabled))
        }
    },
    mapValue: { profile, settings in
        DashboardState(
            name: profile.displayName,
            notificationsEnabled: settings.notificationsEnabled
        )
    }
)
```

You can also package the mapping in a reusable `ComposedBlueprint` and pass it to `.composedBy(blueprint)`.

**Alignment in code**
- `binding(_:send:animation:)` routes writes through actions (`send`) and `process`.
- `directBinding(_:animation:)` mutates state directly for UI-only/performance-heavy cases.
- Both binding APIs preserve SwiftUI transaction animation when available.

**Example**
```swift
TextField(
    "Username",
    text: feature.binding(\.username, send: { .usernameChanged($0) })
)

Slider(
    value: feature.directBinding(\.dragProgress, animation: .spring),
    in: 0...1
)
```

## Goal 7: Test harness for work-driven features

**Goal**
Test `process` + `Work` behavior without spinning up real async dependencies.

**Alignment in code**
- `Tester` runs feature logic with an in-memory state.
- `WorkInspection` asserts operation shape (`assertDone`, `assertRun`, `assertMerge`, `assertConcatenate`, `assertCancel`).
- `feedResult` drives task/stream `Work` by injecting test inputs into generated test plans.

**Example**
```swift
let tester = Tester<MyFeature>(state: .init(id: UUID()))

let loading = tester.send(.refresh) { state in
    // assert state transitions
}

loading.assertRun()

let done = try tester.feedResult(
    for: loading,
    result: .success(["A", "B"])
) { state in
    // assert final state
}

done.assertDone()
```

Note: the current public `Tester` initializer is available when `State: Identifiable`.

## Goal 8: Actor-based broadcasting utility

**Goal**
Provide a lightweight actor for decoupled, asynchronous message broadcast.

**Alignment in code**
- `Broadcaster` manages subscribers as `AsyncStream` continuations keyed by `ReferenceIdentifier`.
- `subscribe(id:)` returns a stream and auto-cleans terminated subscribers.
- `broadcast(message:)` fan-outs messages to active subscribers.
- `finish()` terminates all streams.

**Example**
```swift
struct AppEvent: BroadcastMessage {
    let date: Date
    let title: String
    let sender: ReferenceIdentifier?
}

let broadcaster = Broadcaster()
let stream = await broadcaster.subscribe(id: feature.id)

Task {
    for await message in stream {
        print(message.title)
    }
}

await broadcaster.broadcast(
    message: AppEvent(date: .now, title: "Refresh completed", sender: feature.id)
)
```

## Current Gap

There is no dedicated preview-only helper API in the current implementation. SwiftUI previews can use `Feature`, `FeatureContainer`, and `Shared` directly.
