//
//  dynamicMemberLookup.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

import Testing
@testable import Supervision

// MARK: - Test Feature

private struct CounterFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State: Equatable {
        var count: Int = 0
        var name: String = "Counter"
        var isEnabled: Bool = true
    }

    enum Action {
        case increment
        case decrement
        case setName(String)
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .increment:
            context.modify(\.count) { $0 += 1 }
        case .decrement:
            context.modify(\.count) { $0 -= 1 }
        case .setName(let name):
            context.modify(\.name, to: name)
        }
        return .done
    }
}

// MARK: - Tests

@MainActor
@Suite("Supervisor Dynamic Member Lookup")
struct SupervisorDynamicMemberLookupTests {
    @Test("Access state properties via dynamic member lookup")
    func accessProperties() async throws {
        let supervisor = Supervisor<CounterFeature>(
            state: CounterFeature.State(),
            dependency: ()
        )

        // Access properties directly via dynamic member lookup
        #expect(supervisor.count == 0)
        #expect(supervisor.name == "Counter")
        #expect(supervisor.isEnabled == true)
    }

    @Test("Dynamic member lookup reflects state changes")
    func propertiesUpdateAfterAction() async throws {
        let supervisor = Supervisor<CounterFeature>(
            state: CounterFeature.State(),
            dependency: ()
        )

        #expect(supervisor.count == 0)

        supervisor.send(.increment)
        #expect(supervisor.count == 1)

        supervisor.send(.increment)
        #expect(supervisor.count == 2)

        supervisor.send(.decrement)
        #expect(supervisor.count == 1)
    }

    @Test("Dynamic member lookup works with string properties")
    func stringPropertyAccess() async throws {
        let supervisor = Supervisor<CounterFeature>(
            state: CounterFeature.State(),
            dependency: ()
        )

        #expect(supervisor.name == "Counter")

        supervisor.send(.setName("Updated"))
        #expect(supervisor.name == "Updated")
    }

    @Test("Dynamic member lookup returns correct values")
    func equivalentToStateAccess() async throws {
        let supervisor = Supervisor<CounterFeature>(
            state: CounterFeature.State(count: 42, name: "Test", isEnabled: false),
            dependency: ()
        )

        // Dynamic member lookup should return the correct state values
        #expect(supervisor.count == 42)
        #expect(supervisor.name == "Test")
        #expect(supervisor.isEnabled == false)
    }
}
