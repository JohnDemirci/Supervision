//
//  BatchBuilderTests.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

@testable import Supervision
import Testing

// MARK: - Test Helpers

private struct TestState {
    var name: String = "John"
    var lastName: String = "Demirci"
    var age: Int = 30
    var isActive: Bool = true
    var profile: Profile = Profile()

    struct Profile {
        var bio: String = "Hello"
        var website: String = "example.com"
    }
}

private func withBatchBuilder<T>(
    state: inout TestState,
    _ body: (borrowing BatchBuilder<TestState>) -> T
) -> T {
    withUnsafeMutablePointer(to: &state) { pointer in
        let builder = BatchBuilder<TestState>(
            mutateFn: { $0.apply(&pointer.pointee) },
            statePointer: UnsafePointer(pointer)
        )
        return body(builder)
    }
}

// MARK: - Tests

@MainActor
@Suite("BatchBuilder")
struct BatchBuilderTests {
    @Test("Set values via dynamic member lookup")
    func setValues() async throws {
        var state = TestState()

        withBatchBuilder(state: &state) { batch in
            batch.set(\.name, to: "Jane")
            batch.set(\.age, to: 25)
        }

        #expect(state.name == "Jane")
        #expect(state.age == 25)
    }

    @Test("Multiple mutations in single batch")
    func multipleMutations() async throws {
        var state = TestState()

        withBatchBuilder(state: &state) { batch in
            batch.set(\.name, to: "Alice")
            batch.set(\.lastName, to: "Smith")
            batch.set(\.age, to: 28)
            batch.set(\.isActive, to: false)
        }

        #expect(state.name == "Alice")
        #expect(state.lastName == "Smith")
        #expect(state.age == 28)
        #expect(state.isActive == false)
    }

    @Test("Read then modify same property")
    func readThenModify() async throws {
        var state = TestState(age: 30)

        let currentAge = state.age
        withBatchBuilder(state: &state) { batch in
            batch.set(\.age, to: currentAge + 1)
        }

        #expect(state.age == 31)
    }

    @Test("Mutations are applied immediately")
    func mutationsAppliedImmediately() async throws {
        var state = TestState(name: "Original")

        withBatchBuilder(state: &state) { batch in
            batch.set(\.name, to: "Updated")
        }

        #expect(state.name == "Updated")
    }
}
