//
//  GranularObservationTests.swift
//  Supervision
//
//  Created on 01/04/26.
//

@testable import Supervision
import Foundation
import Testing
import Observation

// MARK: - Test Feature

struct ObservationTestFeature: FeatureProtocol {
    struct State: Equatable {
        var count: Int = 0
        var name: String = ""
        var isEnabled: Bool = false
        var items: [String] = []
        var user: User = User()

        struct User: Equatable {
            var firstName: String = ""
            var lastName: String = ""
            var age: Int = 0
        }
    }

    typealias Dependency = Void

    enum Action: Sendable {
        case incrementCount
        case setCount(Int)
        case setName(String)
        case setIsEnabled(Bool)
        case addItem(String)
        case setItems([String])
        case setUserFirstName(String)
        case setUserAge(Int)
        case batchUpdate(count: Int, name: String)
        case multiPropertyUpdate(count: Int, name: String, isEnabled: Bool)
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .incrementCount:
            context.modify(\.count) { $0 += 1 }

        case .setCount(let value):
            context.modify(\.count, to: value)

        case .setName(let value):
            context.modify(\.name, to: value)

        case .setIsEnabled(let value):
            context.modify(\.isEnabled, to: value)

        case .addItem(let item):
            context.modify(\.items) { $0.append(item) }

        case .setItems(let items):
            context.modify(\.items, to: items)

        case .setUserFirstName(let firstName):
            context.modify(\.user.firstName, to: firstName)

        case .setUserAge(let age):
            context.modify(\.user.age, to: age)

        case .batchUpdate(let count, let name):
            context.modify { batch in
                batch.count.wrappedValue = count
                batch.name.wrappedValue = name
            }

        case .multiPropertyUpdate(let count, let name, let isEnabled):
            context.modify(\.count, to: count)
            context.modify(\.name, to: name)
            context.modify(\.isEnabled, to: isEnabled)
        }
        return .done
    }
}

// MARK: - Granular Observation Tests

@MainActor
@Suite("Granular Observation")
struct GranularObservationTests {

    // MARK: - Basic State Access

    @Test("Dynamic member lookup reads state correctly")
    func dynamicMemberLookupReadsState() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(count: 42, name: "Test"),
            dependency: ()
        )

        #expect(supervisor.count == 42)
        #expect(supervisor.name == "Test")
        #expect(supervisor.isEnabled == false)
    }

    @Test("State mutations are reflected in reads")
    func stateMutationsReflectedInReads() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(),
            dependency: ()
        )

        supervisor.send(.setCount(100))
        #expect(supervisor.count == 100)

        supervisor.send(.setName("Updated"))
        #expect(supervisor.name == "Updated")
    }

    // MARK: - Equatable Optimization

    @Test("Same value mutation does not trigger observation")
    func sameValueNoObservation() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(count: 42)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            // Set to same value - should not trigger
            context.modify(\.count, to: 42)
        }

        #expect(mutationCount == 0, "Should not trigger mutation when value unchanged")
    }

    @Test("Different value mutation triggers observation")
    func differentValueTriggersObservation() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(count: 42)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.count, to: 100)
        }

        #expect(mutationCount == 1, "Should trigger mutation when value changed")
        #expect(state.count == 100)
    }

    // MARK: - Nested KeyPath Support

    @Test("Nested keyPath mutation works correctly")
    func nestedKeyPathMutation() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(),
            dependency: ()
        )

        supervisor.send(.setUserFirstName("John"))
        #expect(supervisor.user.firstName == "John")

        supervisor.send(.setUserAge(30))
        #expect(supervisor.user.age == 30)
    }

    @Test("Nested keyPath with same value does not trigger")
    func nestedKeyPathSameValue() {
        var mutationCount = 0
        var state = ObservationTestFeature.State()
        state.user.firstName = "John"

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.user.firstName, to: "John")
        }

        #expect(mutationCount == 0)
    }

    // MARK: - Batch Mutations

    @Test("Batch mutations apply all changes")
    func batchMutationsApplyAll() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(),
            dependency: ()
        )

        supervisor.send(.batchUpdate(count: 50, name: "Batch"))

        #expect(supervisor.count == 50)
        #expect(supervisor.name == "Batch")
    }

    @Test("Multiple mutations in single send apply atomically")
    func multipleMutationsAtomic() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(),
            dependency: ()
        )

        supervisor.send(.multiPropertyUpdate(count: 10, name: "Multi", isEnabled: true))

        #expect(supervisor.count == 10)
        #expect(supervisor.name == "Multi")
        #expect(supervisor.isEnabled == true)
    }

    // MARK: - Array Mutations

    @Test("Array append triggers observation")
    func arrayAppendTriggersObservation() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(items: ["a", "b"])

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.items) { $0.append("c") }
        }

        #expect(mutationCount == 1)
        #expect(state.items == ["a", "b", "c"])
    }

    @Test("Same array value does not trigger")
    func sameArrayNoTrigger() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(items: ["a", "b"])

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.items, to: ["a", "b"])
        }

        #expect(mutationCount == 0)
    }

    // MARK: - Closure Mutations with Equatable Check

    @Test("Closure that doesn't change value skips observation")
    func closureNoChangeSkips() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(count: 10)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            // Closure that results in same value
            context.modify(\.count) { count in
                count = max(0, count)  // Already >= 0
            }
        }

        #expect(mutationCount == 0)
        #expect(state.count == 10)
    }

    @Test("Closure that changes value triggers observation")
    func closureChangesTriggers() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(count: 10)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.count) { count in
                count *= 2
            }
        }

        #expect(mutationCount == 1)
        #expect(state.count == 20)
    }

    // MARK: - Supervisor Integration

    @Test("Supervisor applies mutations correctly")
    func supervisorAppliesMutations() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(),
            dependency: ()
        )

        supervisor.send(.incrementCount)
        supervisor.send(.incrementCount)
        supervisor.send(.incrementCount)

        #expect(supervisor.count == 3)
    }

    // MARK: - Stress Tests

    @Test("Many rapid mutations do not cause issues")
    func manyRapidMutations() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(),
            dependency: ()
        )

        for i in 0..<1000 {
            supervisor.send(.setCount(i))
        }

        #expect(supervisor.count == 999)
    }

    @Test("Alternating property mutations work correctly")
    func alternatingPropertyMutations() {
        let supervisor = Supervisor<ObservationTestFeature>(
            state: .init(),
            dependency: ()
        )

        for i in 0..<100 {
            supervisor.send(.setCount(i))
            supervisor.send(.setName("Name\(i)"))
            supervisor.send(.setIsEnabled(i % 2 == 0))
        }

        #expect(supervisor.count == 99)
        #expect(supervisor.name == "Name99")
        #expect(supervisor.isEnabled == false)
    }

    // MARK: - Edge Cases

    @Test("Empty string to empty string does not trigger")
    func emptyStringToEmptyString() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(name: "")

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.name, to: "")
        }

        #expect(mutationCount == 0)
    }

    @Test("Zero to zero does not trigger")
    func zeroToZero() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(count: 0)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.count, to: 0)
        }

        #expect(mutationCount == 0)
    }

    @Test("False to false does not trigger")
    func falseToFalse() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(isEnabled: false)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.isEnabled, to: false)
        }

        #expect(mutationCount == 0)
    }

    @Test("True to true does not trigger")
    func trueToTrue() {
        var mutationCount = 0
        var state = ObservationTestFeature.State(isEnabled: true)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<ObservationTestFeature.State>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.isEnabled, to: true)
        }

        #expect(mutationCount == 0)
    }
}
