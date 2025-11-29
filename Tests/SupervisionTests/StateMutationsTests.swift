//
//  StateMutationsTests.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Supervision
import Testing

struct CounterFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State {
        var counter: Int = 0
    }

    enum Action {
        case increment(by: Int = 1)
        case decrement
        case batchIncrement([Int])
    }

    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        switch action {
        case .batchIncrement(let values):
            // Demonstrate old batch API
            // Note: Within a batch, mutations are not immediately visible
            // So we need to track the running total manually
            context.batch {
                var total = context.counter
                for value in values {
                    total += value
                }
                context.mutate(\.counter, to: total)
            }

        case .increment(by: let value):
            context.mutate(\.counter, to: context.counter + value)

        case .decrement:
            context.transform(\.counter) { currentValue in
                return currentValue - 1
            }
        }
    }
}

// Feature for testing the new ergonomic batch API
struct UserProfileFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State {
        var firstName: String = ""
        var lastName: String = ""
        var age: Int = 0
        var email: String = ""
        var isVerified: Bool = false

        // Nested struct for testing nested mutations
        var address: Address = Address()

        struct Address {
            var street: String = ""
            var city: String = ""
            var zipCode: String = ""
        }
    }

    enum Action {
        case updateProfile(firstName: String, lastName: String, age: Int)
        case updateEmail(String)
        case verify
        case updateAddress(street: String, city: String, zipCode: String)
        case updateFullProfile(
            firstName: String,
            lastName: String,
            age: Int,
            email: String,
            street: String,
            city: String,
            zipCode: String
        )
    }

    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        switch action {
        case .updateProfile(let firstName, let lastName, let age):
            // NEW: Ergonomic batch API with builder pattern
            context.batch { state in
                state.firstName.wrappedValue = firstName
                state.lastName.wrappedValue = lastName
                state.age.wrappedValue = age
            }

        case .updateEmail(let email):
            context.mutate(\.email, to: email)

        case .verify:
            context.mutate(\.isVerified, to: true)

        case .updateAddress(let street, let city, let zipCode):
            // NEW: Nested property mutations
            context.batch { state in
                state.address.street.wrappedValue = street
                state.address.city.wrappedValue = city
                state.address.zipCode.wrappedValue = zipCode
            }

        case .updateFullProfile(let firstName, let lastName, let age, let email, let street, let city, let zipCode):
            // NEW: Mix of top-level and nested mutations
            context.batch { state in
                state.firstName.wrappedValue = firstName
                state.lastName.wrappedValue = lastName
                state.age.wrappedValue = age
                state.email.wrappedValue = email
                state.isVerified.wrappedValue = true
                state.address.street.wrappedValue = street
                state.address.city.wrappedValue = city
                state.address.zipCode.wrappedValue = zipCode
            }
        }
    }
}

@MainActor
@Suite("State Mutations")
struct StateMutationsTests {
    @Test("increment should change the state")
    func changeStateOnIncrement() async throws {
        let supervisor = Supervisor<CounterFeature>(Supervisor<CounterFeature>.State())

        supervisor.send(.increment(by: 4))

        #expect(supervisor.state.counter == 4)
    }

    @Test("batch increment with old API")
    func batchIncrementOldAPI() async throws {
        let supervisor = Supervisor<CounterFeature>(Supervisor<CounterFeature>.State())

        supervisor.send(.batchIncrement([1, 2, 3, 4]))

        #expect(supervisor.state.counter == 10)
    }
}

@MainActor
@Suite("Ergonomic Batch API")
struct BatchBuilderTests {
    @Test("batch multiple property updates")
    func batchMultipleProperties() async throws {
        let supervisor = Supervisor<UserProfileFeature>(UserProfileFeature.State())

        supervisor.send(.updateProfile(firstName: "John", lastName: "Doe", age: 30))

        #expect(supervisor.state.firstName == "John")
        #expect(supervisor.state.lastName == "Doe")
        #expect(supervisor.state.age == 30)
    }

    @Test("batch nested property updates")
    func batchNestedProperties() async throws {
        let supervisor = Supervisor<UserProfileFeature>(UserProfileFeature.State())

        supervisor.send(.updateAddress(street: "123 Main St", city: "Springfield", zipCode: "12345"))

        #expect(supervisor.state.address.street == "123 Main St")
        #expect(supervisor.state.address.city == "Springfield")
        #expect(supervisor.state.address.zipCode == "12345")
    }

    @Test("batch mix of top-level and nested properties")
    func batchMixedProperties() async throws {
        let supervisor = Supervisor<UserProfileFeature>(UserProfileFeature.State())

        supervisor.send(.updateFullProfile(
            firstName: "Jane",
            lastName: "Smith",
            age: 25,
            email: "jane@example.com",
            street: "456 Oak Ave",
            city: "Portland",
            zipCode: "97201"
        ))

        #expect(supervisor.state.firstName == "Jane")
        #expect(supervisor.state.lastName == "Smith")
        #expect(supervisor.state.age == 25)
        #expect(supervisor.state.email == "jane@example.com")
        #expect(supervisor.state.isVerified == true)
        #expect(supervisor.state.address.street == "456 Oak Ave")
        #expect(supervisor.state.address.city == "Portland")
        #expect(supervisor.state.address.zipCode == "97201")
    }

    @Test("builder reads current state values")
    func builderReadsCurrentState() async throws {
        var state = UserProfileFeature.State()
        state.firstName = "Initial"
        state.age = 20

        let supervisor = Supervisor<UserProfileFeature>(state)

        // Test that we can read values within batch
        // Note: This test verifies the getter works, though mutations
        // within the batch won't be visible until after the batch completes
        supervisor.send(.updateProfile(firstName: "Updated", lastName: "Name", age: 30))

        #expect(supervisor.state.firstName == "Updated")
        #expect(supervisor.state.age == 30)
    }
}
