# Feature Modeling

Use this reference for `FeatureBlueprint`, `State`, `Action`, `Dependency`,
`Context`, and `Work` changes. The examples target Supervision v3.3.0.

## Define a feature

A feature is a lightweight blueprint. Keep live state in the nested observable value,
represent every input as an action, and declare external capabilities as dependencies.

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

`FeatureBlueprint` requires `init()`. A property-free blueprint receives the
synthesized initializer. If the blueprint stores values, supply an initializer that
satisfies the protocol without turning runtime services into blueprint state.

Use the `featureID` when work, messages, or diagnostics must be correlated with this
specific live feature. Do not invent a second identity for the same purpose.

## Mutate through Context

`Context<State>` is borrowed and noncopyable. Read or mutate its state synchronously
inside `process`, and never capture it in an escaping closure or asynchronous task.
Return work for anything that outlives the action handler.

Keep validation and immediate derived mutations in the action branch that owns them:

```swift
case .nameChanged(let value):
    context.name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return .done
```

## Model asynchronous effects

Dependencies should expose small `Sendable` capabilities. A one-shot effect uses
`.run` and maps its `Result` into another action:

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

Always handle both success and failure when mapping a throwing dependency to
`Result`. Keep loading and error state transitions explicit and testable.

## Choose the appropriate Work

| API | Use |
| --- | --- |
| `.done` | No follow-up effect |
| `.run` | One async operation that maps a result into an action |
| `.subscribe` | Consume an `AsyncSequence` and emit an action per value or error |
| `.fireAndForget` | Run work that intentionally emits no action |
| `.send` | Emit an action through the work pipeline |
| `.cancel` | Cancel work with a cancellation identifier |
| `.merge` | Run independent work concurrently |
| `.concatenate` | Run ordered work sequentially |
| `.map` / `.flatMap` | Transform emitted actions or expand them into more work |

Use `.named`, `.priority`, `.debounce`, `.throttle`, and `.cancellable` to configure
run work. Throttled work must have a cancellation identifier. `merge` and
`concatenate` accept at most five non-`.done` operations in v3.3.0, and a grouped work
cannot have one shared cancellation identifier.

Cancellation behavior is deliberate:

- `cancelInFlight: true`: cancel the existing operation and start the new one.
- `cancelInFlight: false`: keep the existing operation and discard the new one.
- `.cancel(id)`: cancel identified work immediately.

## Model subscriptions

Use `.subscribe` for a long-lived `AsyncSequence`, give it a cancellation identifier,
and provide an action that stops it:

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

Subscriptions are fire-and-forget and do not block later action processing. Feature
deinitialization finishes its processing stream and cancels outstanding work.
