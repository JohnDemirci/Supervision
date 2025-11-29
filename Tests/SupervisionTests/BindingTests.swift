//
//  BindingTests.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Supervision
import SwiftUI
import Testing

// MARK: - Test Features

struct FormFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State {
        var username: String = ""
        var email: String = ""
        var age: Int = 18
        var isSubscribed: Bool = false

        // Validation state
        var usernameError: String? = nil
        var emailError: String? = nil
    }

    enum Action {
        case usernameChanged(String)
        case emailChanged(String)
        case ageChanged(Int)
        case subscriptionToggled(Bool)
    }

    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        switch action {
        case .usernameChanged(let username):
            // Validate and trim username
            let trimmed = username.trimmingCharacters(in: .whitespaces)
            context.mutate(\.username, to: trimmed)

            if trimmed.count < 3 {
                context.mutate(\.usernameError, to: "Username must be at least 3 characters")
            } else {
                context.mutate(\.usernameError, to: nil)
            }

        case .emailChanged(let email):
            // Lowercase email
            let lowercased = email.lowercased()
            context.mutate(\.email, to: lowercased)

            // Validate email
            if lowercased.contains("@") && lowercased.contains(".") {
                context.mutate(\.emailError, to: nil)
            } else {
                context.mutate(\.emailError, to: "Invalid email format")
            }

        case .ageChanged(let age):
            // Clamp age
            let clamped = max(0, min(120, age))
            context.mutate(\.age, to: clamped)

        case .subscriptionToggled(let isSubscribed):
            context.mutate(\.isSubscribed, to: isSubscribed)
        }
    }
}

struct UIStateFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State {
        var volume: Double = 50
        var brightness: Double = 75
        var selectedTab: Int = 0
    }

    enum Action {
        // No actions needed for pure UI state
    }

    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        // No actions to process
    }
}

// MARK: - Tests

@MainActor
@Suite("SwiftUI Binding Tests")
struct BindingTests {

    // MARK: - Action-Based Binding Tests

    @Test("action binding sends action on value change")
    func testActionBindingSendsAction() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        // Create binding
        let usernameBinding = supervisor.binding(\.username, send: { .usernameChanged($0) })

        // Initial value
        #expect(usernameBinding.wrappedValue == "")

        // Set value through binding (simulates SwiftUI control)
        usernameBinding.wrappedValue = "  john  "

        // Action processed, validation applied (trimmed)
        #expect(supervisor.state.username == "john")
        #expect(supervisor.state.usernameError == nil)
    }

    @Test("action binding validates input")
    func testActionBindingValidation() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        let usernameBinding = supervisor.binding(\.username, send: { .usernameChanged($0) })

        // Set short username
        usernameBinding.wrappedValue = "ab"

        #expect(supervisor.state.username == "ab")
        #expect(supervisor.state.usernameError == "Username must be at least 3 characters")

        // Set valid username
        usernameBinding.wrappedValue = "alice"

        #expect(supervisor.state.username == "alice")
        #expect(supervisor.state.usernameError == nil)
    }

    @Test("action binding transforms email to lowercase")
    func testActionBindingTransformsEmail() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        let emailBinding = supervisor.binding(\.email, send: { .emailChanged($0) })

        // Set email with uppercase
        emailBinding.wrappedValue = "JOHN@EXAMPLE.COM"

        // Email is lowercased
        #expect(supervisor.state.email == "john@example.com")
        #expect(supervisor.state.emailError == nil)
    }

    @Test("action binding clamps age value")
    func testActionBindingClampsAge() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        let ageBinding = supervisor.binding(\.age, send: { .ageChanged($0) })

        // Set age above maximum
        ageBinding.wrappedValue = 150

        // Age is clamped to 120
        #expect(supervisor.state.age == 120)

        // Set age below minimum
        ageBinding.wrappedValue = -5

        // Age is clamped to 0
        #expect(supervisor.state.age == 0)
    }

    @Test("action binding works with toggle")
    func testActionBindingToggle() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        let subscriptionBinding = supervisor.binding(\.isSubscribed, send: { .subscriptionToggled($0) })

        #expect(subscriptionBinding.wrappedValue == false)

        // Toggle on
        subscriptionBinding.wrappedValue = true
        #expect(supervisor.state.isSubscribed == true)

        // Toggle off
        subscriptionBinding.wrappedValue = false
        #expect(supervisor.state.isSubscribed == false)
    }

    // MARK: - Direct Binding Tests

    @Test("direct binding mutates state without actions")
    func testDirectBindingNoActions() async throws {
        let supervisor = Supervisor<UIStateFeature>(.init())

        let volumeBinding = supervisor.directBinding(\.volume)

        #expect(volumeBinding.wrappedValue == 50)

        // Set value directly
        volumeBinding.wrappedValue = 75.5

        // State updated immediately, no action processing
        #expect(supervisor.state.volume == 75.5)
    }

    @Test("direct binding updates state immediately")
    func testDirectBindingImmediate() async throws {
        let supervisor = Supervisor<UIStateFeature>(.init())

        let brightnessBinding = supervisor.directBinding(\.brightness)

        // Multiple rapid changes (like slider dragging)
        brightnessBinding.wrappedValue = 80
        #expect(supervisor.state.brightness == 80)

        brightnessBinding.wrappedValue = 85
        #expect(supervisor.state.brightness == 85)

        brightnessBinding.wrappedValue = 90
        #expect(supervisor.state.brightness == 90)
    }

    @Test("direct binding works with integer selection")
    func testDirectBindingIntegerSelection() async throws {
        let supervisor = Supervisor<UIStateFeature>(.init())

        let tabBinding = supervisor.directBinding(\.selectedTab)

        #expect(tabBinding.wrappedValue == 0)

        // Change tab
        tabBinding.wrappedValue = 2
        #expect(supervisor.state.selectedTab == 2)

        tabBinding.wrappedValue = 1
        #expect(supervisor.state.selectedTab == 1)
    }

    // MARK: - Comparison Tests

    @Test("action binding vs direct binding behavior")
    func testActionVsDirectBindingComparison() async throws {
        // Feature with both business logic and UI state
        struct MixedFeature: FeatureProtocol {
            typealias Dependency = Void

            struct State {
                var name: String = ""          // Business logic
                var sliderValue: Double = 0    // UI state
            }

            enum Action {
                case nameChanged(String)
            }

            func process(action: Action, context: borrowing Context<State>, dependency: Void) {
                switch action {
                case .nameChanged(let name):
                    // Transform to uppercase
                    context.mutate(\.name, to: name.uppercased())
                }
            }
        }

        let supervisor = Supervisor<MixedFeature>(.init())

        // Action binding: transforms value
        let nameBinding = supervisor.binding(\.name, send: { .nameChanged($0) })
        nameBinding.wrappedValue = "alice"
        #expect(supervisor.state.name == "ALICE")  // Transformed by action

        // Direct binding: no transformation
        let sliderBinding = supervisor.directBinding(\.sliderValue)
        sliderBinding.wrappedValue = 42.5
        #expect(supervisor.state.sliderValue == 42.5)  // Direct, no processing
    }

    @Test("bindings read current state correctly")
    func testBindingsReadCurrentState() async throws {
        let supervisor = Supervisor<FormFeature>(.init(
            username: "initial",
            email: "test@example.com",
            age: 25,
            isSubscribed: true
        ))

        // Action binding getter
        let usernameBinding = supervisor.binding(\.username, send: { .usernameChanged($0) })
        #expect(usernameBinding.wrappedValue == "initial")

        // Direct binding getter
        let ageBinding = supervisor.directBinding(\.age)
        #expect(ageBinding.wrappedValue == 25)

        // Bindings reflect state changes
        supervisor.send(.usernameChanged("updated"))
        #expect(usernameBinding.wrappedValue == "updated")
    }

    // MARK: - Transaction & Animation Tests

    @Test("action binding with custom animation parameter")
    func testActionBindingWithAnimation() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        // Binding with spring animation
        let binding = supervisor.binding(
            \.isSubscribed,
            send: { .subscriptionToggled($0) },
            animation: .spring(response: 0.3)
        )

        // Set value (animation is applied via withAnimation internally)
        binding.wrappedValue = true

        #expect(supervisor.state.isSubscribed == true)
    }

    @Test("direct binding with custom animation parameter")
    func testDirectBindingWithAnimation() async throws {
        let supervisor = Supervisor<UIStateFeature>(.init())

        // Binding with easeInOut animation
        let binding = supervisor.directBinding(\.volume, animation: .easeInOut)

        // Set value (animation is applied via withAnimation internally)
        binding.wrappedValue = 75.0

        #expect(supervisor.state.volume == 75.0)
    }

    @Test("action binding without animation parameter")
    func testActionBindingNoAnimation() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        // Binding without animation (immediate update)
        let binding = supervisor.binding(\.age, send: { .ageChanged($0) })

        binding.wrappedValue = 30

        #expect(supervisor.state.age == 30)
    }

    @Test("direct binding without animation parameter")
    func testDirectBindingNoAnimation() async throws {
        let supervisor = Supervisor<UIStateFeature>(.init())

        // Binding without animation (immediate update)
        let binding = supervisor.directBinding(\.selectedTab)

        binding.wrappedValue = 2

        #expect(supervisor.state.selectedTab == 2)
    }

    @Test("hybrid pattern - direct binding with completion action")
    func testHybridPatternDirectBindingWithCompletionAction() async throws {
        struct VolumeFeature: FeatureProtocol {
            typealias Dependency = Void

            struct State {
                var volume: Double = 50
                var lastCommittedVolume: Double = 50
            }

            enum Action {
                case volumeChangeCompleted(Double)
            }

            func process(action: Action, context: borrowing Context<State>, dependency: Void) {
                switch action {
                case .volumeChangeCompleted(let volume):
                    // Log, trigger haptics, save to UserDefaults, etc.
                    context.mutate(\.lastCommittedVolume, to: volume)
                }
            }
        }

        let supervisor = Supervisor<VolumeFeature>(.init())

        // Direct binding for smooth dragging
        let volumeBinding = supervisor.directBinding(\.volume, animation: .spring)

        // Simulate user dragging slider
        volumeBinding.wrappedValue = 60
        volumeBinding.wrappedValue = 70
        volumeBinding.wrappedValue = 75

        #expect(supervisor.state.volume == 75)
        #expect(supervisor.state.lastCommittedVolume == 50) // Not yet committed

        // Simulate user releasing slider (onEditingChanged: false)
        supervisor.send(.volumeChangeCompleted(supervisor.state.volume))

        #expect(supervisor.state.lastCommittedVolume == 75) // Now committed
    }

    @Test("multiple bindings to same supervisor")
    func testMultipleBindingsToSameSupervisor() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        let usernameBinding = supervisor.binding(\.username, send: { .usernameChanged($0) })
        let emailBinding = supervisor.binding(\.email, send: { .emailChanged($0) })
        let ageBinding = supervisor.binding(\.age, send: { .ageChanged($0) }, animation: .easeInOut)

        // All bindings work independently
        usernameBinding.wrappedValue = "alice"
        emailBinding.wrappedValue = "ALICE@EXAMPLE.COM"
        ageBinding.wrappedValue = 30

        #expect(supervisor.state.username == "alice")
        #expect(supervisor.state.email == "alice@example.com") // Lowercased
        #expect(supervisor.state.age == 30)
    }

    @Test("binding animation parameter is optional")
    func testBindingAnimationParameterOptional() async throws {
        let supervisor = Supervisor<FormFeature>(.init())

        // Can omit animation parameter (defaults to nil)
        let binding1 = supervisor.binding(\.username, send: { .usernameChanged($0) })
        let binding2 = supervisor.directBinding(\.age)

        binding1.wrappedValue = "test"
        binding2.wrappedValue = 25

        #expect(supervisor.state.username == "test")
        #expect(supervisor.state.age == 25)
    }
}
