# Testing Supervision Features

Use `Tester` to execute synchronous action handling and inspect the returned `Work`
without running live dependencies. The examples target Supervision v3.3.0 and Swift
Testing.

## Assert state and work together

```swift
import Supervision
import Testing

@Test
func incrementUpdatesCount() throws {
    let tester = Tester<CounterFeature>(initialState: .init())

    try tester.send(.increment) { state in
        #expect(state.count == 1)
    }
    .assertDone()
}
```

The closure passed to `send` observes state after the synchronous `process` call.
Always assert the returned work shape as well as the state transition.

## Feed one-shot results

Assert `.run`, then supply the result that the dependency would have produced:

```swift
@Test
func refreshLoadsRemoteCount() throws {
    let tester = Tester<RemoteCounterFeature>(initialState: .init())

    let run = try tester.send(.refresh) { state in
        #expect(state.isLoading)
    }
    .assertRun()

    let completed = tester.feedResult(
        Result<Int, Error>.success(42),
        inspection: run
    ) { state in
        #expect(state.count == 42)
        #expect(!state.isLoading)
    }

    try completed.assertDone()
}
```

Add a failure-result test when failure changes state or behavior. Feeding a result
executes the work's result mapper and sends the mapped action through the tester.

## Test subscriptions

Feed each stream element individually, assert the resulting action's work, then test
the action that cancels the subscription:

```swift
let subscription = try tester.send(.startObserving).assertRun()
#expect(subscription.isSubscription)

let handledValue = tester.feedValue(
    42,
    inspection: subscription
) { state in
    #expect(state.count == 42)
}

try handledValue.assertDone()
try tester.send(.stopObserving).assertCancel()
```

## Inspect coordination and configuration

Use the inspection matching the returned operation:

- `assertDone()`
- `assertRun()`
- `assertCancel()`
- `assertMerge()`
- `assertConcatenate()`

`RunInspection` exposes the run configuration, including `cancelInFlight`,
`debounce`, `throttle`, and `isSubscription`. Assert configuration when it is part of
the behavior being changed, especially cancellation and timing semantics.

The grouped inspection's public `work.operation` contains its child work. Verify
meaningful ordering for concatenation and membership for merges rather than merely
asserting the outer type.

## Finish every inspection

The harness reports unfinished expectations. Complete every returned inspection by
asserting it and feeding any expected result or value. Call `forget()` only when the
test deliberately does not care about completion. Non-subscription fire-and-forget
run inspections are marked forgotten by `assertRun()`.

After changing a feature, cover:

- each affected synchronous state transition,
- success and relevant failure mappings for one-shot work,
- cancellation IDs and `cancelInFlight` behavior when used,
- subscription values and explicit cancellation,
- merge or concatenate structure when ordering or concurrency matters.

Run the consuming repository's Swift tests, normally with `swift test`.
