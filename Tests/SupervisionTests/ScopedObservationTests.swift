//
//  ScopedObservationTests.swift
//  SupervisionTests
//
//  Created on 01/28/26.
//

@testable import Supervision
import Foundation
import Observation
import Testing

@MainActor
@Suite("Scoped Observation")
struct ScopedObservationTests {

    struct ScopedObservationFeature: FeatureBlueprint {
        struct State: Equatable {
            var parent1 = Parent1()

            struct Parent1: Equatable {
                var parent2 = Parent2()
            }

            struct Parent2: Equatable {
                var parent3 = Parent3()
            }

            struct Parent3: Equatable {
                var child: Int = 0
            }
        }

        typealias Dependency = Void

        enum Action: Sendable {
            case replaceParent3(State.Parent3)
        }

        func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
            switch action {
            case .replaceParent3(let parent3):
                context.modify(\.parent1.parent2.parent3, to: parent3)
            }
            return .done
        }
    }

    final class ChangeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count: Int = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            let current = count
            lock.unlock()
            return current
        }
    }

    @Test("Chained scope triggers observation when parent replaces")
    func chainedScopeTriggersOnParentReplacement() async {
        let feature = Feature<ScopedObservationFeature>(state: .init(), dependency: ())
        let counter = ChangeCounter()

        withObservationTracking {
            _ = feature
                .scope(\.parent1)
                .scope(\.parent2)
                .scope(\.parent3)
                .value(\.child)
        } onChange: {
            counter.increment()
        }

        var newParent3 = ScopedObservationFeature.State.Parent3()
        newParent3.child = 1
        feature.send(.replaceParent3(newParent3))

        let triggered = await waitUntil(timeout: .seconds(1)) {
            counter.value == 1
        }
        #expect(triggered)
    }

    @Test("Multi-arg scope triggers observation when parent replaces")
    func multiArgScopeTriggersOnParentReplacement() async {
        let feature = Feature<ScopedObservationFeature>(state: .init(), dependency: ())
        let counter = ChangeCounter()

        withObservationTracking {
            _ = feature
                .scope(\.parent1, \.parent2, \.parent3)
                .value(\.child)
        } onChange: {
            counter.increment()
        }

        var newParent3 = ScopedObservationFeature.State.Parent3()
        newParent3.child = 2
        feature.send(.replaceParent3(newParent3))

        let triggered = await waitUntil(timeout: .seconds(1)) {
            counter.value == 1
        }
        #expect(triggered)
    }

    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10),
        _ condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return condition()
    }
}
