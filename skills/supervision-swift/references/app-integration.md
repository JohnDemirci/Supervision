# Application Integration

Use this reference for feature ownership, containers, SwiftUI, previews,
compositions, shared projections, and cross-feature messages. The examples target
Supervision v3.3.0.

## Own a live Feature

`Feature` is `@MainActor`, observable, and the source-of-truth owner for a blueprint's
state. A dependency-free feature can be created directly:

```swift
@State private var counter = Feature<CounterFeature>(state: .init())
```

Use `FeatureContainer` when an application needs dependency mapping, reuse by stable
identity, environment injection, or multiple coordinated features:

```swift
struct AppDependencies: Sendable {
    var loadCount: @Sendable () async throws -> Int
}

let container = FeatureContainer(
    dependency: AppDependencies(loadCount: { 42 })
)

let counter = container.feature(
    type: RemoteCounterFeature.self,
    state: .init()
) { dependencies in
    RemoteCounterFeature.Dependency(loadCount: dependencies.loadCount)
}
```

Identity controls reuse:

- Non-`Identifiable` state uses the feature type, so one live instance per feature
  type is returned by a container.
- `Identifiable` state combines its `id` with the feature type, allowing multiple
  instances of one feature type.
- A request for an identity already alive returns that feature. Its new initial state
  is ignored and its dependency closure is not evaluated.
- Live containers store features weakly. Keep a strong owner for every feature that
  must remain alive.

## Inject a container into SwiftUI

Install a container at an application or scene boundary and recover its dependency
type with `@ContainerEnvironment`:

```swift
RootView()
    .containerManagement(container)

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

Missing environment injection is a precondition failure. Put the injection above
every view that reads the container.

## Bind SwiftUI controls

Prefer `binding` when a user edit represents behavior and should travel through an
action:

```swift
TextField(
    "Username",
    text: feature.binding(\.username, send: Action.usernameChanged)
)
```

Use `directBinding` only when bypassing action logic is intentional, such as UI-local
drag progress. Use `isPresent(keyPath:)` for optional presentation state; writing
`false` clears the optional, while writing `true` does not create a value.

These bindings preserve SwiftUI transaction animations. Equatable direct bindings
skip writes that assign the current value.

## Preserve view-owned initialization

Use `FeatureStateView` when a mounted view transitions from an idle placeholder to one
or more supplied features:

```swift
@State private var counterState: FeatureState<CounterFeature> = .idle
@State private var profileState: FeatureState<ProfileFeature> = .idle

var body: some View {
    FeatureStateView(state: $counterState, $profileState) { counter, profile in
        DashboardView(counter: counter, profile: profile)
    }
    .instantiate(with: counter, profile)
}
```

Bindings and features must be passed in the same order. Once initialized for that
view identity, assigning `.idle` does not reset or replace the attached feature.

## Build previews

Preview factories are available only in `DEBUG` builds:

```swift
let preview = Feature<CounterFeature>.makePreview(
    state: .init(count: 42),
    previewActionMapper: nil
)
```

An action mapper may replace an outgoing action or return `nil` to let the original
action continue. Compositions use `ComposedFeature<MyComposition>.preview(...)`.

## Compose existing features

Use `Composed` to project state and route actions across live parent features without
copying ownership. Keep the composition's observable `State` nested in the composition:

```swift
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
    }

    let parents: Parents

    func mapAction(_ action: Action) -> Parents.Actions {
        switch action {
        case .increment: (.increment, nil)
        case .toggle: (nil, .toggle)
        }
    }

    func mapState() -> State {
        parents.withFeatures { counter, toggle in
            State(count: counter.count, isEnabled: toggle.isEnabled)
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

Create the parent pack with features in the same order as its parameter pack and
include the composition type in its identity:

```swift
let parents = ParentFeatures(
    features: counter, toggle,
    composedBy: DashboardComposition.self
)

let dashboard = container.composedFeature(
    composed: DashboardComposition(parents: parents)
)
```

Each optional element returned from `mapAction` corresponds to one parent; `nil`
means no action for that parent. State projection updates are observation-driven and
asynchronous, so do not assume a parent action refreshes the composition inline.

## Share or broadcast selectively

Use `Shared(feature:keypath:)` for an observable projection of one parent value. Use
`Broadcaster` for looser typed application-wide events. Prefer composition when the
features have an explicit coordinating relationship.

Every broadcaster subscription creates an independent `AsyncStream`. Subscriptions
registered under the same feature ID share the union of registered message kinds.
Dropping a stream removes its continuation; `finish()` terminates all streams.
