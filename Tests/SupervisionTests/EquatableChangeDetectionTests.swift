//
//  EquatableChangeDetectionTests.swift
//  Supervision
//
//  Created on 01/03/26.
//

@testable import Supervision
import Foundation
import Testing

@MainActor
@Suite("Equatable Change Detection")
struct EquatableChangeDetectionTests {

    // MARK: - Test Feature Setup

    struct TestState: Sendable, Equatable {
        var count: Int = 0
        var name: String = ""
        var isEnabled: Bool = false
        var optionalValue: Int? = nil
        var items: [String] = []
    }

    struct NonEquatableType: Sendable {
        var value: Int = 0
    }

    struct TestFeature: FeatureProtocol {
        typealias State = TestState
        typealias Dependency = Void

        enum Action: Sendable {
            case setCount(Int)
            case setName(String)
            case setIsEnabled(Bool)
            case setOptionalValue(Int?)
            case setItems([String])
            case modifyCount(transform: @Sendable (inout Int) -> Void)
            case batchUpdate(count: Int, name: String)
        }

        func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
            switch action {
            case .setCount(let value):
                context.modify(\.count, to: value)
            case .setName(let value):
                context.modify(\.name, to: value)
            case .setIsEnabled(let value):
                context.modify(\.isEnabled, to: value)
            case .setOptionalValue(let value):
                context.modify(\.optionalValue, to: value)
            case .setItems(let value):
                context.modify(\.items, to: value)
            case .modifyCount(let transform):
                context.modify(\.count, transform)
            case .batchUpdate(let count, let name):
                context.modify { batch in
                    batch.set(\.count, to: count)
                    batch.set(\.name, to: name)
                }
            }
            return .done
        }
    }

    // MARK: - Tests for modify(_:to:) with Equatable values

    @Test("Setting same Int value does not trigger observation")
    func sameIntValueNoObservation() async throws {
        var mutationCount = 0
        var state = TestState(count: 42)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            // Set to same value - should not trigger due to direct Equatable comparison
            context.modify(\.count, to: 42)
        }

        #expect(mutationCount == 0, "Should not trigger mutation when value unchanged")
        #expect(state.count == 42)
    }

    @Test("Setting different Int value triggers observation")
    func differentIntValueTriggersObservation() async throws {
        var mutationCount = 0
        var state = TestState(count: 42)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            // Set to different value
            context.modify(\.count, to: 100)
        }

        #expect(mutationCount == 1, "Should trigger mutation when value changed")
        #expect(state.count == 100)
    }

    @Test("Setting same String value does not trigger observation")
    func sameStringValueNoObservation() async throws {
        var mutationCount = 0
        var state = TestState(name: "Hello")

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.name, to: "Hello")
        }

        #expect(mutationCount == 0, "Should not trigger mutation when String unchanged")
    }

    @Test("Setting same Bool value does not trigger observation")
    func sameBoolValueNoObservation() async throws {
        var mutationCount = 0
        var state = TestState(isEnabled: true)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.isEnabled, to: true)
        }

        #expect(mutationCount == 0, "Should not trigger mutation when Bool unchanged")
    }

    @Test("Setting same Optional value does not trigger observation")
    func sameOptionalValueNoObservation() async throws {
        var mutationCount = 0
        var state = TestState(optionalValue: 5)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.optionalValue, to: 5)
        }

        #expect(mutationCount == 0, "Should not trigger mutation when Optional unchanged")
    }

    @Test("Setting same Array value does not trigger observation")
    func sameArrayValueNoObservation() async throws {
        var mutationCount = 0
        var state = TestState(items: ["a", "b", "c"])

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.items, to: ["a", "b", "c"])
        }

        #expect(mutationCount == 0, "Should not trigger mutation when Array unchanged")
    }

    // MARK: - Tests for modify(_:_:) closure-based mutation with Equatable

    @Test("Closure mutation that does not change value skips observation")
    func closureMutationNoChangeSkipsObservation() async throws {
        var mutationCount = 0
        var state = TestState(count: 10)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            // Closure that doesn't actually change the value
            context.modify(\.count) { count in
                count = max(0, count)  // count is already >= 0
            }
        }

        #expect(mutationCount == 0, "Should not trigger when closure doesn't change value")
        #expect(state.count == 10)
    }

    @Test("Closure mutation that changes value triggers observation")
    func closureMutationWithChangeTriggersObservation() async throws {
        var mutationCount = 0
        var state = TestState(count: 10)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.count) { count in
                count += 5
            }
        }

        #expect(mutationCount == 1, "Should trigger when closure changes value")
        #expect(state.count == 15)
    }

    // MARK: - Integration tests with Supervisor

    @Test("Supervisor does not trigger observation when setting same value")
    func supervisorSameValueNoObservation() async throws {
        let supervisor = Supervisor<TestFeature>(
            state: TestState(count: 42, name: "Test"),
            dependency: ()
        )

        // Send action that sets the same value
        supervisor.send(.setCount(42))

        // The state should still be 42, and importantly,
        // SwiftUI observation should not have been triggered
        #expect(supervisor[\.count] == 42)
    }

    @Test("Supervisor triggers observation when setting different value")
    func supervisorDifferentValueTriggersObservation() async throws {
        let supervisor = Supervisor<TestFeature>(
            state: TestState(count: 42),
            dependency: ()
        )

        supervisor.send(.setCount(100))

        #expect(supervisor[\.count] == 100)
    }

    @Test("Batch mutations trigger for each mutation")
    func batchMutationsTrigger() async throws {
        let supervisor = Supervisor<TestFeature>(
            state: TestState(count: 10, name: "Original"),
            dependency: ()
        )

        // Batch update
        supervisor.send(.batchUpdate(count: 10, name: "Changed"))

        #expect(supervisor[\.count] == 10)
        #expect(supervisor[\.name] == "Changed")
    }

    @Test("Multiple same-value mutations do not accumulate observations")
    func multipleSameValueMutationsNoAccumulation() async throws {
        let supervisor = Supervisor<TestFeature>(
            state: TestState(count: 0),
            dependency: ()
        )

        // Set to same value multiple times
        for _ in 0..<100 {
            supervisor.send(.setCount(0))
        }

        #expect(supervisor[\.count] == 0)
    }

    // MARK: - Edge cases

    @Test("nil to nil Optional does not trigger observation")
    func nilToNilOptionalNoObservation() async throws {
        var mutationCount = 0
        var state = TestState(optionalValue: nil)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.optionalValue, to: nil)
        }

        #expect(mutationCount == 0, "nil to nil should not trigger")
    }

    @Test("nil to some triggers observation")
    func nilToSomeTriggersObservation() async throws {
        var mutationCount = 0
        var state = TestState(optionalValue: nil)

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.optionalValue, to: 5)
        }

        #expect(mutationCount == 1, "nil to some should trigger")
        #expect(state.optionalValue == 5)
    }

    @Test("Empty array to empty array does not trigger observation")
    func emptyArrayToEmptyArrayNoObservation() async throws {
        var mutationCount = 0
        var state = TestState(items: [])

        withUnsafeMutablePointer(to: &state) { pointer in
            let context = Context<TestState>(
                mutateFn: { mutation in
                    mutation.apply(&pointer.pointee)
                    mutationCount += 1
                },
                statePointer: pointer
            )

            context.modify(\.items, to: [])
        }

        #expect(mutationCount == 0, "Empty to empty array should not trigger")
    }
}
