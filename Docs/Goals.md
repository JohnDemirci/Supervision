# Supervision Goals

This document describes what Supervision is trying to provide today and how those goals map to the current implementation.

Supervision is a lightweight feature architecture for Swift centered on value-type state, explicit async work, reusable feature identity, and an inspection-driven testing story.

## Core Principles

- Feature logic is modeled through `FeatureBlueprint` (`State`, `Action`, `Dependency`, and `process`).
- State is value-based and observable (`State: ObservableValue`, and in many features also `Equatable`).
- State mutations happen through `Context`, with `Feature` as the source-of-truth owner.
- Side effects are explicit through `Work` and executed by `Worker`.
- Feature identity is stable and supports reuse via `FeatureContainer`.
- Testing is built into the architecture via `Tester` and `Inspection`.

## Goal 1: Lightweight feature model

**Goal**

Provide a small, explicit unit of application logic with clear boundaries for state, input, dependencies, and follow-up work.

**Implemented in code**

- `FeatureBlueprint` defines the shape of a feature in [Sources/Supervision/FeatureBlueprint.swift](../Sources/Supervision/FeatureBlueprint.swift).
- `Feature` owns the live state and is the action entrypoint in [Sources/Supervision/Feature.swift](../Sources/Supervision/Feature.swift).
- `process(action:context:)` receives a borrowed `Context<State>` and returns `Work<Action, Dependency>`.

**Example**

```swift
import Supervision
import ValueObservation

struct CounterFeature: FeatureBlueprint {
    @ObservableValue
    struct State {
        var count = 0
        var isLoading = false
    }

    enum Action: Sendable {
        case increment
        case refresh
        case response(Result<Int, Error>)
    }

    struct Dependency: Sendable {
        var load: @Sendable () async throws -> Int
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .increment:
            context.count += 1
            return .done

        case .refresh:
            context.isLoading = true
            return .run { dependency in
                try await dependency.load()
            } map: { .response($0) }

        case .response(.success(let value)):
            context.count = value
            context.isLoading = false
            return .done

        case .response(.failure):
            context.isLoading = false
            return .done
        }
    }
}
```

## Goal 2: Value-type observation with fine grained updates

**Goal**

Make value-type feature state observable without forcing broad store invalidation for every change.

**Implemented in code**

- `FeatureBlueprint.State` must conform to `ObservableValue`.
- `Feature` exposes value reads through `state` and dynamic member lookup.
- `Shared` creates focused observable projections for a single feature key path or a mapped value.
- `ComposedFeature` derives observable state from other live features.

**Example**

```swift
import Supervision
import ValueObservation

struct ProfileFeature: FeatureBlueprint {
    @ObservableValue
    struct State {
        var firstName = ""
        var lastName = ""
    }

    enum Action: Sendable {
        case setFirstName(String)
        case setLastName(String)
    }

    typealias Dependency = Void

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .setFirstName(let value):
            context.firstName = value
        case .setLastName(let value):
            context.lastName = value
        }
        return .done
    }
}

let feature = Feature<ProfileFeature>(state: .init())
let sharedFirstName = Shared(feature: feature, keypath: \.firstName)
let currentValue = sharedFirstName.value
```

## Goal 3: Zero-copy reads and controlled mutation via `Context`

**Goal**

Keep state access efficient while constraining writes to feature processing and derived-state recomputation.

**Implemented in code**

- `Context` is `~Copyable` and `~Escapable` in [Sources/Supervision/Context.swift](../Sources/Supervision/Context.swift).
- `Context` holds an internal pointer to feature state and exposes borrowed reads through `_read`.
- Feature logic mutates state through `context.state` or dynamic-member writes such as `context.count += 1`.
- `Composed.updateState(context:)` uses the same mechanism for in-place derived-state updates.

**Example**

```swift
func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
    if context.state.count > 100 {
        context.state.isOverLimit = true
    }

    context.state.lastUpdatedAt = .now
    context.state.count += 1

    return .done
}
```

## Goal 4: Explicit async work and lifecycle control

**Goal**

Represent side effects as values and make their lifecycle visible and controllable.

**Implemented in code**

- `Work` models `.done`, `.cancel`, `.run`, `.merge`, and `.concatenate`.
- `Work` supports `named`, `cancellable`, `priority`, `throttle`, `debounce`, `map`, `flatMap`, `send`, `fireAndForget`, and `subscribe`.
- `Worker` is the actor that performs work, tracks in-flight tasks, applies cancellation rules, and records throttle windows.
- `Feature.send(_:)` converts actions into `Work` and delegates execution to `Worker`.

**Example**

```swift
return .run { dependency in
    try await dependency.load()
} map: { .response($0) }
.cancellable(id: "profile.load", cancelInFlight: true)
.debounce(for: .milliseconds(250))
```

```swift
return .merge(
    .run { dependency in try await dependency.loadHeader() } map: { .headerLoaded($0) },
    .run { dependency in try await dependency.loadBody() } map: { .bodyLoaded($0) }
)
```

```swift
return .concatenate(
    .send(.stepOneStarted),
    .run { dependency in try await dependency.performStepOne() } map: { .stepOneFinished($0) },
    .run { dependency in try await dependency.performStepTwo() } map: { .stepTwoFinished($0) }
)
```

## Goal 5: Stable identity and reusable feature instances

**Goal**

Give live features stable identity so they can be reused across the app instead of recreated ad hoc.

**Implemented in code**

- `ReferenceIdentifier` is the identity type.
- `Feature.makeID(from:)` combines `state.id` and feature type when `State: Identifiable`.
- `Feature.makeID()` falls back to feature-type identity when state is not identifiable.
- `FeatureContainer` caches live `Feature` instances in a weak-to-weak `NSMapTable`.

**Example**

```swift
import Supervision
import ValueObservation

struct InboxFeature: FeatureBlueprint {
    @ObservableValue
    struct State: Identifiable {
        let id: String
        var title = ""
    }

    enum Action: Sendable {
        case rename(String)
    }

    typealias Dependency = Void

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .rename(let value):
            context.title = value
            return .done
        }
    }
}

let container = FeatureContainer(dependency: ())
let first = container.feature(state: InboxFeature.State(id: "inbox"))
let second = container.feature(state: InboxFeature.State(id: "inbox"))

let sameInstance = first === second
```

## Goal 6: SwiftUI and Preview Support

**Goal**

Make live features convenient to use from SwiftUI while keeping the architectural tradeoffs explicit.

**Implemented in code**

- `binding(_:send:animation:)` routes SwiftUI writes through actions.
- `directBinding(_:animation:)` directly mutates feature state for UI-only or high-frequency interactions.
- `isPresent(keyPath:animation:)` creates `Binding<Bool>` for optional presentation state.
- `Feature.makePreview(state:previewActionMapper:)` is available in `DEBUG` builds for preview-only wiring.

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

```swift
#if DEBUG
let preview = Feature<MyFeature>.makePreview(
    state: .init(),
    previewActionMapper: { action in
        switch action {
        case .onAppear:
            .loadMockData
        default:
            nil
        }
    }
)
#endif
```

## Goal 7: Inter-feature communication through Shared and Broadcasting

**Goal**

Support communication patterns that do not require collapsing everything into one feature.

**Implemented in code**

- `Shared` projects a focused value from one live feature for another consumer to observe.
- `Broadcaster` provides actor-based async pub/sub for loosely coupled message fan-out.
- `BroadcastMessage` standardizes the message shape with `date`, `title`, and `sender`.

**Example**

```swift
let sharedCount = Shared(feature: counterFeature, keypath: \.count)
let count = sharedCount.value
```

```swift
import Foundation
import Supervision

struct AppEvent: BroadcastMessage {
    let date: Date
    let title: String
    let sender: ReferenceIdentifier?
}

let broadcaster = Broadcaster()
let stream = await broadcaster.subscribe(id: counterFeature.id)

Task {
    for await event in stream {
        print(event.title)
    }
}

await broadcaster.broadcast(
    message: AppEvent(
        date: .now,
        title: "Counter updated",
        sender: counterFeature.id
    )
)
```

## Goal 8: Feature composition from existing Features

**Goal**

Build a derived feature from existing live features without introducing a separate parent store.

**Implemented in code**

- `ParentFeatures` groups any number of live features using parameter packs.
- `Composed` defines how a derived feature maps actions and derives state.
- `ComposedFeature` owns the derived state and fans actions out to the underlying parent features.
- `updateState(context:)` lets composed state be recomputed in place.

**Example**

```swift
import Supervision
import ValueObservation

// Assuming the `CounterFeature` and `ToggleFeature` definitions
// shown in Docs/Composition.md.

@ObservableValue
struct DashboardState {
    var count: Int
    var isEnabled: Bool
}

struct DashboardComposition: Composed {
    enum Action: Sendable {
        case increment
        case setEnabled(Bool)
        case synchronize
    }

    typealias State = DashboardState
    typealias Parents = ParentFeatures<CounterFeature, ToggleFeature>

    let parents: Parents

    func mapAction(_ action: Action) -> Parents.Actions {
        switch action {
        case .increment:
            (.increment, nil)
        case .setEnabled(let value):
            (nil, .setEnabled(value))
        case .synchronize:
            (.increment, .setEnabled(true))
        }
    }

    func mapState() -> State {
        parents.withFeatures { counter, toggle in
            DashboardState(
                count: counter.count,
                isEnabled: toggle.isEnabled
            )
        }
    }

    func updateState(context: borrowing Context<State>) {
        parents.withFeatures { counter, toggle in
            context.count = counter.count
            context.isEnabled = toggle.isEnabled
        }
    }
}
```

For a full composition walkthrough, see [Docs/Composition.md](./Composition.md).

## Goal 9: Testing harness

**Goal**

Test state transitions and work shape without running real async dependencies.

**Implemented in code**

- `Tester` runs `process(action:context:)` against in-memory state.
- `Inspection` is the common protocol for asserting returned `Work`.
- `DoneInspection`, `CancelInspection`, `RunInspection`, `MergeInspection`, and `ConcatenateInspection` model the different work shapes.
- `feedResult(_:inspection:)` and `feedValue(_:inspection:)` drive test plans produced by `.run` and `.subscribe`.

**Example**

```swift
import Supervision
import XCTest

@MainActor
func testRefreshFlow() throws {
    let tester = Tester<CounterFeature>(initialState: .init())

    let inspection = tester.send(.refresh) { state in
        XCTAssertTrue(state.isLoading)
    }

    let run = try inspection.assertRun()

    let done = tester.feedResult(
        .success(10),
        inspection: run
    ) { state in
        XCTAssertEqual(state.count, 10)
        XCTAssertFalse(state.isLoading)
    }

    try done.assertDone()
}
```

## Summary

Supervision currently implements:

- a feature boundary through `FeatureBlueprint`,
- a live runtime through `Feature`,
- explicit side effects through `Work` and `Worker`,
- reusable feature identity through `FeatureContainer`,
- SwiftUI bindings and preview helpers,
- focused sharing and broadcasting utilities,
- feature composition from existing live features,
- and an inspection-driven testing harness.

The package is still under active development, but the APIs described above are the ones that exist in the checked-in code today.
