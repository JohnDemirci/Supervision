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
    @Test("Read values via dynamic member lookup")
    func readValues() async throws {
        var state = TestState()

        withBatchBuilder(state: &state) { batch in
            #expect(batch.name.wrappedValue == "John")
            #expect(batch.lastName.wrappedValue == "Demirci")
            #expect(batch.age.wrappedValue == 30)
            #expect(batch.isActive.wrappedValue == true)
        }
    }

    @Test("Set values via dynamic member lookup")
    func setValues() async throws {
        var state = TestState()

        withBatchBuilder(state: &state) { batch in
            batch.name.wrappedValue = "Jane"
            batch.age.wrappedValue = 25
        }

        #expect(state.name == "Jane")
        #expect(state.age == 25)
    }

    @Test("Multiple mutations in single batch")
    func multipleMutations() async throws {
        var state = TestState()

        withBatchBuilder(state: &state) { batch in
            batch.name.wrappedValue = "Alice"
            batch.lastName.wrappedValue = "Smith"
            batch.age.wrappedValue = 28
            batch.isActive.wrappedValue = false
        }

        #expect(state.name == "Alice")
        #expect(state.lastName == "Smith")
        #expect(state.age == 28)
        #expect(state.isActive == false)
    }

    @Test("Nested property access")
    func nestedPropertyAccess() async throws {
        var state = TestState()

        withBatchBuilder(state: &state) { batch in
            // Read nested
            #expect(batch.profile.bio.wrappedValue == "Hello")
            #expect(batch.profile.website.wrappedValue == "example.com")

            // Write nested
            batch.profile.bio.wrappedValue = "Updated bio"
            batch.profile.website.wrappedValue = "new-site.com"
        }

        #expect(state.profile.bio == "Updated bio")
        #expect(state.profile.website == "new-site.com")
    }

    @Test("Read then modify same property")
    func readThenModify() async throws {
        var state = TestState(age: 30)

        withBatchBuilder(state: &state) { batch in
            let currentAge = batch.age.wrappedValue
            batch.age.wrappedValue = currentAge + 1
        }

        #expect(state.age == 31)
    }

    @Test("Mutations are applied immediately")
    func mutationsAppliedImmediately() async throws {
        var state = TestState(name: "Original")

        withBatchBuilder(state: &state) { batch in
            batch.name.wrappedValue = "Updated"
            // Read back immediately - should see updated value
            #expect(batch.name.wrappedValue == "Updated")
        }
    }
}
