# Currently under development 🚧
Please wait for releases, though you are welcome look at the code and use it in your own pet projects.

# Supervision

Supervision is a lightweight feature architecture for Swift with:

- value-type observable state,
- explicit async work modeling (`Work`),
- stable feature identity for reuse (`FeatureContainer`),
- and a built-in testing harness (`Tester` / `WorkInspection`).

## Requirements

- Swift `6.2`
- Platforms:
  - iOS `26`
  - macOS `26`
  - tvOS `26`
  - watchOS `26`
  - visionOS `26`

## Installation

Add Supervision with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/JohnDemirci/Supervision.git", branch: "main")
]
```

Then add the product to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Supervision", package: "Supervision")
    ]
)
```

## Quick Start

```swift
import Supervision
import ValueObservation

struct CounterFeature: FeatureBlueprint {
    @ObservableValue
    struct State: Identifiable, Equatable {
        let id: String
        var count = 0
        var isLoading = false
        var username = ""
        var dragProgress = 0.0
    }

    enum Action: Sendable {
        case increment
        case refresh
        case response(Result<Int, Error>)
        case usernameChanged(String)
    }

    struct Dependency: Sendable {
        var loadRemoteCount: @Sendable () async throws -> Int
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .increment:
            context.modify(\.count) { $0 += 1 }
            return .done

        case .refresh:
            context.modify(\.isLoading, to: true)
            return .run { env in
                try await env.loadRemoteCount()
            } map: { .response($0) }
            .cancellable(id: "counter.load", cancelInFlight: true)
            .debounce(for: .milliseconds(250))

        case .response(.success(let value)):
            context.modify { batch in
                batch.set(\.count, to: value)
                batch.set(\.isLoading, to: false)
            }
            return .done

        case .response(.failure):
            context.modify(\.isLoading, to: false)
            return .done

        case .usernameChanged(let username):
            context.modify(\.username, to: username.trimmingCharacters(in: .whitespaces))
            return .done
        }
    }
}

let feature = Feature<CounterFeature>(
    state: .init(id: "main"),
    dependency: .init(loadRemoteCount: { 42 })
)

feature.send(.increment)
print(feature.count) // 1
```

## Core Types

- `FeatureBlueprint`: defines `State`, `Action`, `Dependency`, and `process`.
- `Feature`: runtime owner of state and action dispatch (`send`).
- `Context`: zero-copy reads and controlled state mutation (`modify`).
- `Work`: effect model (`run`, `subscribe`, `cancel`, `merge`, `concatenate`, etc.).
- `FeatureContainer`: weakly-cached feature reuse by stable identity.
- `Tester` / `WorkInspection`: deterministic testing for `Work`-driven logic.
- `Shared`: focused observable projection for a feature key path.
- `Broadcaster`: actor-based async pub/sub utility.

## Important Notes

- `FeatureBlueprint` requires:
  - `State: Equatable & ObservableValue`
  - `Action: Sendable`
  - `Dependency: Sendable`
  - `init()`
- `State` is expected to be a value type (`struct`).
- `Feature`, `FeatureContainer`, `Tester`, and `Shared` are `@MainActor`.
- `Work.merge(...)` and `Work.concatenate(...)` accept at most 5 non-`.done` works.

## Reusing Features With `FeatureContainer`

```swift
import Supervision

struct AppDependency: Sendable {
    var loadRemoteCount: @Sendable () async throws -> Int
}

let container = FeatureContainer(
    dependency: AppDependency(loadRemoteCount: { 42 })
)

let f1 = container.feature(state: CounterFeature.State(id: "inbox")) { dep in
    CounterFeature.Dependency(loadRemoteCount: dep.loadRemoteCount)
}

let f2 = container.feature(state: CounterFeature.State(id: "inbox")) { dep in
    CounterFeature.Dependency(loadRemoteCount: dep.loadRemoteCount)
}

let sameInstance = (f1 === f2) // true while retained
```

## SwiftUI Bindings

Use action-based bindings by default:

```swift
TextField(
    "Username",
    text: feature.binding(\.username, send: { .usernameChanged($0) })
)
```

Use `directBinding` for UI-only / high-frequency animated input:

```swift
Slider(
    value: feature.directBinding(\.dragProgress, animation: .spring),
    in: 0...1
)
```

## Testing

`Tester` gives you in-memory state tests with `WorkInspection` assertions.

```swift
import XCTest
import Supervision

@MainActor
func testRefreshFlow() throws {
    let tester = Tester<CounterFeature>(state: .init(id: "test"))

    let inspection = tester.send(.refresh) { state in
        XCTAssertTrue(state.isLoading)
    }

    inspection.assertRun()

    let done = try tester.feedResult(
        for: inspection,
        result: .success(10)
    ) { state in
        XCTAssertEqual(state.count, 10)
        XCTAssertFalse(state.isLoading)
    }

    done.assertDone()
}
```

Note: the public `Tester` initializer is currently available when `State: Identifiable`.

## Shared Projections

```swift
let sharedCount = Shared(feature: feature, keypath: \.count)
let value = sharedCount.value
```

## Broadcasting

```swift
import Foundation
import Supervision

struct AppEvent: BroadcastMessage {
    let date: Date
    let title: String
    let sender: ReferenceIdentifier?
}

let broadcaster = Broadcaster()
let stream = await broadcaster.subscribe(id: feature.id)

Task {
    for await event in stream {
        print(event.title)
    }
}

await broadcaster.broadcast(
    message: AppEvent(
        date: .now,
        title: "Counter updated",
        sender: feature.id
    )
)
```

## Development

```bash
swift build
swift test
swift package describe
```

## More Docs

- `Docs/Goals.md`
