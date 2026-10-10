# Supervision

A feature-oriented state management architecture for SwiftUI.

Supervision gives Swift applications a predictable place to model state changes,
dependencies, and asynchronous work. It keeps views focused on presentation while
feature behavior remains explicit, composable, and testable.

## Contents

- [What is Supervision?](#what-is-supervision)
- [When should I use it?](#when-should-i-use-it)
- [How it works](#how-it-works)
- [Concurrency and lifetime](#concurrency-and-lifetime)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Asynchronous work](#asynchronous-work)
- [Dependencies and feature containers](#dependencies-and-feature-containers)
- [SwiftUI integration](#swiftui-integration)
- [Feature composition](#feature-composition)
- [Shared values and cross-feature events](#shared-values-and-cross-feature-events)
- [Testing](#testing)
- [API overview](#api-overview)
- [Project status](#project-status)
- [Development](#development)

## What is Supervision?

Supervision organizes application logic into features. Each feature defines:

- value-based observable state,
- the actions it can handle,
- the dependencies it needs, and
- a `process` function that mutates state and describes any work to perform.

State changes happen synchronously through a controlled `Context`. Asynchronous
behavior is returned as a `Work` value that can run a task, subscribe to a stream,
cancel an operation, or coordinate multiple operations. Results flow back into the
feature as actions, preserving a clear, unidirectional path through the application.

Supervision is designed for applications that have outgrown scattered `@State`
properties and ad hoc tasks, but do not need a heavyweight application framework.

## When should I use it?

Supervision is a good fit when your application has:

- multiple screens or feature domains with their own state and behavior,
- API calls, persistence, subscriptions, or other asynchronous effects,
- work that needs cancellation, debouncing, throttling, or coordination,
- dependencies that should be replaceable in previews and tests,
- state or actions that need to be composed across features, or
- business logic that should be tested without executing live effects.

For temporary state that belongs to a single view, SwiftUI's `@State` is usually all
you need. Supervision is most useful when state represents feature or application
behavior.

## How it works

```text
View ──▶ Action ──▶ Feature.process ──▶ State mutation
                              └──▶ Work ──▶ Result action
```

The architecture is built around a few principles:

- **Value-based state:** feature state is modeled as an observable value type.
- **Unidirectional actions:** views and effects communicate with features by sending
  typed actions.
- **Controlled mutation:** state is writable only while an action is being processed.
- **Effects as values:** asynchronous behavior is described with `Work` rather than
  launched directly from feature logic.
- **Explicit dependencies:** external services are supplied to features instead of
  being accessed globally.
- **Testable behavior:** tests can inspect work and feed controlled results back into
  a feature.

## Concurrency and lifetime

`Feature`, `FeatureContainer`, `ComposedFeature`, and `Shared` are isolated to the
main actor. Calling `send` processes the action and its immediate state mutations
synchronously on that actor. Any returned work is then submitted to an actor-backed
worker.

Ordinary work is consumed in submission order. A non-fire-and-forget operation must
finish before the worker advances to the next submitted operation. Subscriptions and
fire-and-forget work run independently so long-lived tasks do not block later work,
and cancellation work is handled immediately instead of waiting in the queue.

When a feature is deallocated, its processing stream is finished and all outstanding
tracked and untracked tasks are cancelled.

## Requirements

- Swift 6.2
- iOS 26 or later
- macOS 26 or later
- tvOS 26 or later
- watchOS 26 or later
- visionOS 26 or later
- Swift Package Manager

The package currently enables Swift's experimental `LifetimeDependence` and
`Lifetimes` features.

## Installation

Add Supervision to the dependencies in your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/JohnDemirci/Supervision.git",
        from: "3.3.0"
    ),
]
```

Then add the product to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Supervision", package: "Supervision"),
    ]
)
```

Import the library wherever you define or use a feature:

```swift
import Supervision
```

## Quick start

Start by defining a feature's state and the actions that can change it:

```swift
import Supervision

struct CounterFeature: FeatureBlueprint {
    typealias Dependency = Void

    @ObservableValue
    struct State {
        var count = 0
    }

    enum Action: Sendable {
        case increment
        case decrement
    }

    func process(
        action: Action,
        context: borrowing Context<State>,
        featureID: ReferenceIdentifier
    ) -> FeatureWork {
        switch action {
        case .increment:
            context.count += 1

        case .decrement:
            context.count -= 1
        }

        return .done
    }
}
```

Feature state should be an `@ObservableValue` structure. Actions and dependencies
must be `Sendable`, and the feature itself must be constructible with `init()`. The
`featureID` parameter is the stable identity of the live feature and can be used to
correlate work, messages, or diagnostics with that instance.

A `Feature` owns the live state and provides the action entry point:

```swift
let counter = Feature<CounterFeature>(state: .init())

counter.send(.increment)
print(counter.count) // 1
```

Because `Feature` participates in Swift Observation, SwiftUI tracks the state values
read by a view:

```swift
import SwiftUI
import Supervision

@MainActor
struct CounterView: View {
    @State private var counter = Feature<CounterFeature>(state: .init())

    var body: some View {
        VStack {
            Text("Count: \(counter.count)")

            HStack {
                Button("Decrement") {
                    counter.send(.decrement)
                }

                Button("Increment") {
                    counter.send(.increment)
                }
            }
        }
    }
}
```

## Asynchronous work

A feature mutates immediate state in `process`, then returns `Work` for anything
asynchronous. The work receives the feature's dependencies and maps its result back
into an action.

```swift
struct RemoteCounterFeature: FeatureBlueprint {
    @ObservableValue
    struct State {
        var count = 0
        var isLoading = false
    }

    enum Action: Sendable {
        case refresh
        case response(Result<Int, Error>)
    }

    struct Dependency: Sendable {
        var loadCount: @Sendable () async throws -> Int
    }

    private enum CancellationID: Hashable, Sendable {
        case refresh
    }

    func process(
        action: Action,
        context: borrowing Context<State>,
        featureID: ReferenceIdentifier
    ) -> FeatureWork {
        switch action {
        case .refresh:
            context.isLoading = true

            return .run { dependency in
                try await dependency.loadCount()
            } map: { result in
                .response(result)
            }
            .cancellable(id: CancellationID.refresh, cancelInFlight: true)

        case .response(.success(let count)):
            context.count = count
            context.isLoading = false
            return .done

        case .response(.failure):
            context.isLoading = false
            return .done
        }
    }
}
```

`Work` supports the common forms of effect coordination:

| API | Purpose |
| --- | --- |
| `.run` | Perform a one-shot async operation and map its result into an action |
| `.subscribe` | Consume an `AsyncSequence` and send an action for each value |
| `.fireAndForget` | Perform work that does not produce an action |
| `.cancel` | Cancel work registered with a cancellation identifier |
| `.merge` | Run independent work concurrently |
| `.concatenate` | Run work sequentially |
| `.send` | Emit an action as a work operation |
| `.cancellable` | Identify work and choose how in-flight work is handled |
| `.debounce` | Delay work until a quiet period has elapsed |
| `.throttle` | Limit how often identified work starts |
| `.priority` | Set the underlying task priority |
| `.named` | Give the underlying task a diagnostic name |
| `.map` | Transform every action emitted by existing work |
| `.flatMap` | Transform an emitted action into more work |

`merge` and `concatenate` currently accept at most five non-`.done` operations.
Throttled work must also have a cancellation identifier supplied with `cancellable`.

Cancellation identifiers also control duplicate work. With `cancelInFlight: true`, a
new operation cancels and replaces the currently running operation with the same ID.
With `cancelInFlight: false`, the currently running operation wins and the new one is
discarded. Return `.cancel(id)` from another action to cancel identified work
explicitly.

### Long-lived subscriptions

Use `subscribe` to turn values from an `AsyncSequence` into actions. Subscriptions are
always fire-and-forget and should normally have a cancellation identifier:

```swift
case .startObserving:
    return .subscribe { dependency in
        try await dependency.counts()
    } map: { result in
        .countReceived(result)
    }
    .cancellable(id: CancellationID.counts, cancelInFlight: true)

case .stopObserving:
    return .cancel(CancellationID.counts)
```

In this example, `dependency.counts()` returns an async sequence and
`countReceived` handles each value or terminal error through the normal action path.

## Dependencies and feature containers

You can construct a feature directly, or ask a `FeatureContainer` to create and cache
it within an application dependency context.

```swift
struct AppDependencies: Sendable {
    var loadCount: @Sendable () async throws -> Int
}

let container = FeatureContainer(
    dependency: AppDependencies(
        loadCount: { 42 }
    )
)

let counter = container.feature(
    type: RemoteCounterFeature.self,
    state: .init()
) { appDependencies in
    RemoteCounterFeature.Dependency(
        loadCount: appDependencies.loadCount
    )
}
```

For non-`Identifiable` state, the feature type supplies the identity. For
`Identifiable` state, the state identifier is combined with the feature type, allowing
the container to manage multiple instances of the same feature. Live containers use
weak storage, so they do not extend a feature's lifetime solely by caching it.

Identity determines initialization behavior. While a cached feature is alive, another
request for the same identity returns that instance: the new initial state is ignored
and the dependency closure is not evaluated again. Once no owner retains the feature,
the weak cache permits it to be deallocated and a later request creates a new instance.

Containers can be injected through SwiftUI's environment:

```swift
@main
struct ExampleApp: App {
    @State private var container = FeatureContainer(
        dependency: AppDependencies(loadCount: { 42 })
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .containerManagement(container)
        }
    }
}

struct RootView: View {
    @ContainerEnvironment<AppDependencies>
    private var container

    var body: some View {
        RemoteCounterView(
            feature: container.feature(
                type: RemoteCounterFeature.self,
                state: .init()
            ) { dependencies in
                .init(loadCount: dependencies.loadCount)
            }
        )
    }
}
```

`TestingFeatureContainer` provides the same container interface while returning
features explicitly injected by a test or preview.

```swift
let injected = Feature<CounterFeature>(
    state: .init(count: 42)
)

let testContainer = TestingFeatureContainer<Void>(
    features: [injected]
)

let resolved = testContainer.feature(
    type: CounterFeature.self,
    state: .init()
)

#expect(resolved === injected)
```

## SwiftUI integration

### Action-driven bindings

Use `binding` when a control change represents feature behavior. Writes are converted
into actions, preserving unidirectional data flow and providing a place for validation
or side effects.

```swift
TextField(
    "Username",
    text: feature.binding(
        \.username,
        send: { .usernameChanged($0) }
    )
)
```

Use `directBinding` sparingly for presentational or high-frequency state that does not
need feature logic, such as the position of an in-progress drag:

```swift
Slider(
    value: feature.directBinding(\.dragProgress, animation: .spring),
    in: 0...1
)
```

Both binding styles preserve SwiftUI transaction animations.

When the direct-bound value is `Equatable`, Supervision skips writes that would assign
the same value and avoids an unnecessary observation mutation.

For optional presentation state, `isPresent` derives a `Binding<Bool>` that clears the
optional when SwiftUI dismisses the destination:

```swift
.sheet(
    isPresented: feature.isPresent(keyPath: \.selectedItem)
) {
    ItemView(item: feature.selectedItem!)
}
```

Setting this binding to `false` sets the optional to `nil`. Setting it to `true` does
not create a value; the feature must populate the optional through an action.

### View-owned feature initialization

`FeatureStateView` can model the transition from uninitialized views to live
features while preserving those features for the mounted view's identity. It accepts
one or more feature-state bindings:

```swift
@State private var featureState: FeatureState<RemoteCounterFeature> = .idle

var body: some View {
    FeatureStateView(state: $featureState) { feature in
        RemoteCounterView(feature: feature)
    }
    .instantiate(with: counter)
}
```

Initialize several features together by passing bindings and features in the same
order:

```swift
@State private var counterState: FeatureState<RemoteCounterFeature> = .idle
@State private var profileState: FeatureState<ProfileFeature> = .idle

var body: some View {
    FeatureStateView(state: $counterState, $profileState) { counter, profile in
        DashboardView(counter: counter, profile: profile)
    }
    .instantiate(with: counter, profile)
}
```

`idle` is only the pre-initialization state. Once the view is mounted and initialized,
assigning `idle` again does not reset or replace the features attached to that view
identity.

In debug builds, `Feature.makePreview` creates a feature from preview state and can
optionally intercept or remap outgoing actions. Compositions have a corresponding
preview factory:

```swift
let preview = ComposedFeature<DashboardComposition>.preview(
    DashboardComposition(parents: parents)
)
```

## Feature composition

`ComposedFeature` presents state and actions derived from existing parent features.
The parent features remain the sources of truth.

A reusable composition conforms to `Composed` and defines:

- `Parents`, usually a `ParentFeatures` pack,
- `mapAction`, which routes a local action to zero or more parent actions,
- `mapState`, which creates the initial projected state, and
- `updateState`, which refreshes that projection when an observed parent value changes.

The following composition combines the `CounterFeature` from the quick start with a
second feature:

```swift
struct ToggleFeature: FeatureBlueprint {
    typealias Dependency = Void

    @ObservableValue
    struct State {
        var isEnabled = false
    }

    enum Action: Sendable {
        case toggle
    }

    func process(
        action: Action,
        context: borrowing Context<State>,
        featureID: ReferenceIdentifier
    ) -> FeatureWork {
        switch action {
        case .toggle:
            context.isEnabled.toggle()
        }

        return .done
    }
}

struct DashboardComposition: Composed {
    typealias Parents = ParentFeatures<CounterFeature, ToggleFeature>

    @ObservableValue
    struct State {
        var count: Int
        var isEnabled: Bool
    }

    enum Action: Sendable {
        case increment
        case toggle
        case synchronize
    }

    let parents: Parents

    func mapAction(_ action: Action) -> Parents.Actions {
        switch action {
        case .increment:
            (.increment, nil)

        case .toggle:
            (nil, .toggle)

        case .synchronize:
            (.increment, .toggle)
        }
    }

    func mapState() -> State {
        parents.withFeatures { counter, toggle in
            State(
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

Create the parent features, wrap them in `ParentFeatures` in the same order as the
`Parents` type alias, identify the composition type, and ask the container for the
composed feature:

```swift
let container = FeatureContainer(dependency: ())

let counter = container.feature(
    type: CounterFeature.self,
    state: .init()
)

let toggle = container.feature(
    type: ToggleFeature.self,
    state: .init()
)

let parents = ParentFeatures(
    features: counter, toggle,
    composedBy: DashboardComposition.self
)
let dashboard = container.composedFeature(
    composed: DashboardComposition(parents: parents)
)

dashboard.send(.synchronize)
```

The composition type participates in the parent pack's identity. This keeps two
different composition types that use the same parent features from colliding in a
`FeatureContainer`.

Each optional action in `Parents.Actions` corresponds to one parent feature. Returning
`nil` leaves that parent unchanged. In the example, `increment` targets only the
counter, `toggle` targets only the toggle, and `synchronize` dispatches to both.

The composition observes the values read by `mapState`. When either parent changes,
`updateState` refreshes the dashboard projection, including when an action is sent
directly to a parent. Observation propagation is asynchronous, so consumers should
react to the composed feature through Swift Observation rather than assume the
projection changes inline with the parent action.

```swift
counter.send(.increment)
// Observers of dashboard.count are notified when its projection updates.
```

This is useful for dashboards, coordinators, and screens that combine several domains
without copying ownership of their state.

## Shared values and cross-feature events

`Shared` exposes an observable projection of one value from another feature:

```swift
let sharedCount = Shared(
    feature: counter,
    keypath: \.count
)

print(sharedCount.value)
```

`Broadcaster` provides actor-isolated, typed pub/sub over `AsyncStream` for events
between features that should remain otherwise independent. Prefer direct composition
when features have an explicit parent-child relationship; use broadcasting for looser
application-wide notifications.

```swift
import Foundation

enum AppMessageKind: BroadcastMessageKind {
    case counterUpdated
}

struct AppMessage: BroadcastMessage {
    let kind: AppMessageKind
    let date: Date
    let title: String
    let sender: ReferenceIdentifier?
}

let broadcaster = Broadcaster()
let messages = await broadcaster.subscribe(
    to: AppMessageKind.counterUpdated,
    id: counter.id
)

Task {
    for await message in messages {
        print(message.title)
    }
}

await broadcaster.broadcast(
    message: AppMessage(
        kind: .counterUpdated,
        date: .now,
        title: "Counter updated",
        sender: counter.id
    )
)
```

Every `subscribe` call creates an independent stream. Registrations using the same
feature ID share the union of their message kinds, so each active stream for that ID
receives messages matching any kind registered under it. Dropping a stream removes
its continuation; call `finish()` to terminate every remaining stream.

## Testing

`Tester` runs the synchronous part of a feature and returns an `Inspection` describing
the resulting work. Tests can then supply controlled task results or stream values
without calling the live dependency.

```swift
import Supervision
import Testing

@Test
func refreshLoadsTheRemoteCount() throws {
    let tester = Tester<RemoteCounterFeature>(initialState: .init())

    let run = try tester.send(.refresh) { state in
        #expect(state.isLoading)
    }
    .assertRun()

    let done = tester.feedResult(
        Result<Int, Error>.success(42),
        inspection: run
    ) { state in
        #expect(state.count == 42)
        #expect(!state.isLoading)
    }

    try done.assertDone()
}
```

Inspections can assert `.done`, `.run`, `.cancel`, `.merge`, and `.concatenate`
operations. Run inspections also expose configuration such as cancellation behavior,
debounce, throttle, and subscription status.

Subscription tests feed individual sequence elements through `feedValue`, then cancel
the long-lived inspection explicitly:

```swift
let subscription = try tester.send(.startObserving).assertRun()

let handledValue = tester.feedValue(
    42,
    inspection: subscription
) { state in
    #expect(state.count == 42)
}

try handledValue.assertDone()
try tester.send(.stopObserving).assertCancel()
```

The harness deliberately reports unfinished expectations. Every returned inspection
should be asserted and completed, or marked with `forget()` when the test intentionally
does not care about its completion. This makes unverified effects visible instead of
silently discarding them.

## API overview

| Type | Responsibility |
| --- | --- |
| `FeatureBlueprint` | Defines a feature's state, actions, dependencies, and processing |
| `Feature` | Owns observable state and dispatches actions |
| `Context` | Provides scoped state access while processing an action |
| `Work` | Describes asynchronous effects and their coordination |
| `FeatureContainer` | Creates, caches, and injects live features |
| `TestingFeatureContainer` | Resolves explicitly injected features in tests and previews |
| `ComposedFeature` | Projects behavior and state from parent features |
| `Shared` | Observes a selected value owned by another feature |
| `Broadcaster` | Delivers typed asynchronous messages to subscribers |
| `Tester` | Tests state transitions and inspects returned work |
| `Inspection` | Asserts the shape and configuration of returned work |

## Project status

Supervision is actively evolving. It currently requires Swift 6.2, the latest Apple
platform releases listed above, and experimental Swift lifetime features. Review
release notes before upgrading between versions while the public API continues to
settle.

## Development

Build the package and run its tests with Swift Package Manager:

```bash
swift build
swift test
swift package describe
```

Tests live in `Tests/SupervisionTests` and use Swift Testing.

## License

Supervision is available under the [BSD Zero Clause License](LICENSE) (`0BSD`).
