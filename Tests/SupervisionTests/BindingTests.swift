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

    struct State: Equatable {
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
    
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .usernameChanged(let username):
            // Validate and trim username
            let trimmed = username.trimmingCharacters(in: .whitespaces)
            context.modify(\.username, to: trimmed)

            if trimmed.count < 3 {
                context.modify(\.usernameError, to: "Username must be at least 3 characters")
            } else {
                context.modify(\.usernameError, to: nil)
            }
            return .done

        case .emailChanged(let email):
            // Lowercase email
            let lowercased = email.lowercased()
            context.modify(\.email, to: lowercased)

            // Validate email
            if lowercased.contains("@") && lowercased.contains(".") {
                context.modify(\.emailError, to: nil)
            } else {
                context.modify(\.emailError, to: "Invalid email format")
            }
            return .done

        case .ageChanged(let age):
            // Clamp age
            let clamped = max(0, min(120, age))
            context.modify(\.age, to: clamped)
            return .done

        case .subscriptionToggled(let isSubscribed):
            context.modify(\.isSubscribed, to: isSubscribed)
            return .done
        }
    }

}

struct UIStateFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State: Equatable {
        var volume: Double = 50
        var brightness: Double = 75
        var selectedTab: Int = 0
    }

    enum Action {
        // No actions needed for pure UI state
    }
    
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        return .done
    }
}

// MARK: - Tests

@MainActor
@Suite("SwiftUI Binding Tests")
struct BindingTests {

    // MARK: - Action-Based Binding Tests

    @Test("action binding sends action on value change")
    func testActionBindingSendsAction() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        // Create binding
        let usernameBinding = supervisor.binding(\.username, send: { .usernameChanged($0) })

        // Initial value
        #expect(usernameBinding.wrappedValue == "")

        // Set value through binding (simulates SwiftUI control)
        usernameBinding.wrappedValue = "  john  "

        // Action processed, validation applied (trimmed)
        #expect(supervisor.username == "john")
        #expect(supervisor.usernameError == nil)
    }

    @Test("action binding validates input")
    func testActionBindingValidation() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        let usernameBinding = supervisor.binding(\.username, send: { .usernameChanged($0) })

        // Set short username
        usernameBinding.wrappedValue = "ab"

        #expect(supervisor.username == "ab")
        #expect(supervisor.usernameError == "Username must be at least 3 characters")

        // Set valid username
        usernameBinding.wrappedValue = "alice"

        #expect(supervisor.username == "alice")
        #expect(supervisor.usernameError == nil)
    }

    @Test("action binding transforms email to lowercase")
    func testActionBindingTransformsEmail() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        let emailBinding = supervisor.binding(\.email, send: { .emailChanged($0) })

        // Set email with uppercase
        emailBinding.wrappedValue = "JOHN@EXAMPLE.COM"

        // Email is lowercased
        #expect(supervisor.email == "john@example.com")
        #expect(supervisor.emailError == nil)
    }

    @Test("action binding clamps age value")
    func testActionBindingClampsAge() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        let ageBinding = supervisor.binding(\.age, send: { .ageChanged($0) })

        // Set age above maximum
        ageBinding.wrappedValue = 150

        // Age is clamped to 120
        #expect(supervisor.age == 120)

        // Set age below minimum
        ageBinding.wrappedValue = -5

        // Age is clamped to 0
        #expect(supervisor.age == 0)
    }

    @Test("action binding works with toggle")
    func testActionBindingToggle() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        let subscriptionBinding = supervisor.binding(\.isSubscribed, send: { .subscriptionToggled($0) })

        #expect(subscriptionBinding.wrappedValue == false)

        // Toggle on
        subscriptionBinding.wrappedValue = true
        #expect(supervisor.isSubscribed == true)

        // Toggle off
        subscriptionBinding.wrappedValue = false
        #expect(supervisor.isSubscribed == false)
    }

    // MARK: - Direct Binding Tests

    @Test("direct binding mutates state without actions")
    func testDirectBindingNoActions() async throws {
        let supervisor = Supervisor<UIStateFeature>(state: .init(), dependency: ())

        let volumeBinding = supervisor.directBinding(\.volume)

        #expect(volumeBinding.wrappedValue == 50)

        // Set value directly
        volumeBinding.wrappedValue = 75.5

        // State updated immediately, no action processing
        #expect(supervisor.volume == 75.5)
    }

    @Test("direct binding updates state immediately")
    func testDirectBindingImmediate() async throws {
        let supervisor = Supervisor<UIStateFeature>(state: .init(), dependency: ())

        let brightnessBinding = supervisor.directBinding(\.brightness)

        // Multiple rapid changes (like slider dragging)
        brightnessBinding.wrappedValue = 80
        #expect(supervisor.brightness == 80)

        brightnessBinding.wrappedValue = 85
        #expect(supervisor.brightness == 85)

        brightnessBinding.wrappedValue = 90
        #expect(supervisor.brightness == 90)
    }

    @Test("direct binding works with integer selection")
    func testDirectBindingIntegerSelection() async throws {
        let supervisor = Supervisor<UIStateFeature>(state: .init(), dependency: ())

        let tabBinding = supervisor.directBinding(\.selectedTab)

        #expect(tabBinding.wrappedValue == 0)

        // Change tab
        tabBinding.wrappedValue = 2
        #expect(supervisor.selectedTab == 2)

        tabBinding.wrappedValue = 1
        #expect(supervisor.selectedTab == 1)
    }

    // MARK: - Comparison Tests

    @Test("action binding vs direct binding behavior")
    func testActionVsDirectBindingComparison() async throws {
        // Feature with both business logic and UI state
        struct MixedFeature: FeatureProtocol {
            typealias Dependency = Void

            struct State: Equatable {
                var name: String = ""          // Business logic
                var sliderValue: Double = 0    // UI state
            }

            enum Action {
                case nameChanged(String)
            }
            
            func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
                switch action {
                case .nameChanged(let name):
                    // Transform to uppercase
                    context.modify(\.name, to: name.uppercased())
                    return .done
                }
            }
        }

        let supervisor = Supervisor<MixedFeature>(state: .init(), dependency: ())

        // Action binding: transforms value
        let nameBinding = supervisor.binding(\.name, send: { .nameChanged($0) })
        nameBinding.wrappedValue = "alice"
        #expect(supervisor.name == "ALICE")  // Transformed by action

        // Direct binding: no transformation
        let sliderBinding = supervisor.directBinding(\.sliderValue)
        sliderBinding.wrappedValue = 42.5
        #expect(supervisor.sliderValue == 42.5)  // Direct, no processing
    }

    @Test("bindings read current state correctly")
    func testBindingsReadCurrentState() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(
            username: "initial",
            email: "test@example.com",
            age: 25,
            isSubscribed: true
        ), dependency: ())

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
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        // Binding with spring animation
        let binding = supervisor.binding(
            \.isSubscribed,
            send: { .subscriptionToggled($0) },
            animation: .spring(response: 0.3)
        )

        // Set value (animation is applied via withAnimation internally)
        binding.wrappedValue = true

        #expect(supervisor.isSubscribed == true)
    }

    @Test("direct binding with custom animation parameter")
    func testDirectBindingWithAnimation() async throws {
        let supervisor = Supervisor<UIStateFeature>(state: .init(), dependency: ())

        // Binding with easeInOut animation
        let binding = supervisor.directBinding(\.volume, animation: .easeInOut)

        // Set value (animation is applied via withAnimation internally)
        binding.wrappedValue = 75.0

        #expect(supervisor.volume == 75.0)
    }

    @Test("action binding without animation parameter")
    func testActionBindingNoAnimation() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        // Binding without animation (immediate update)
        let binding = supervisor.binding(\.age, send: { .ageChanged($0) })

        binding.wrappedValue = 30

        #expect(supervisor.age == 30)
    }

    @Test("direct binding without animation parameter")
    func testDirectBindingNoAnimation() async throws {
        let supervisor = Supervisor<UIStateFeature>(state: .init(), dependency: ())

        // Binding without animation (immediate update)
        let binding = supervisor.directBinding(\.selectedTab)

        binding.wrappedValue = 2

        #expect(supervisor.selectedTab == 2)
    }

    @Test("hybrid pattern - direct binding with completion action")
    func testHybridPatternDirectBindingWithCompletionAction() async throws {
        struct VolumeFeature: FeatureProtocol {
            func process(action: Action, context: borrowing Supervision.Context<State>) -> FeatureWork {
                switch action {
                case .volumeChangeCompleted(let volume):
                    // Log, trigger haptics, save to UserDefaults, etc.
                    context.modify(\.lastCommittedVolume, to: volume)
                    return .done
                }
            }
            
            typealias Dependency = Void

            struct State: Equatable {
                var volume: Double = 50
                var lastCommittedVolume: Double = 50
            }

            enum Action {
                case volumeChangeCompleted(Double)
            }
        }

        let supervisor = Supervisor<VolumeFeature>(state: .init(), dependency: ())

        // Direct binding for smooth dragging
        let volumeBinding = supervisor.directBinding(\.volume, animation: .spring)

        // Simulate user dragging slider
        volumeBinding.wrappedValue = 60
        volumeBinding.wrappedValue = 70
        volumeBinding.wrappedValue = 75

        #expect(supervisor.volume == 75)
        #expect(supervisor.lastCommittedVolume == 50) // Not yet committed

        // Simulate user releasing slider (onEditingChanged: false)
        supervisor.send(.volumeChangeCompleted(supervisor.volume))

        #expect(supervisor.lastCommittedVolume == 75) // Now committed
    }

    @Test("multiple bindings to same supervisor")
    func testMultipleBindingsToSameSupervisor() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        let usernameBinding = supervisor.binding(\.username, send: { .usernameChanged($0) })
        let emailBinding = supervisor.binding(\.email, send: { .emailChanged($0) })
        let ageBinding = supervisor.binding(\.age, send: { .ageChanged($0) }, animation: .easeInOut)

        // All bindings work independently
        usernameBinding.wrappedValue = "alice"
        emailBinding.wrappedValue = "ALICE@EXAMPLE.COM"
        ageBinding.wrappedValue = 30

        #expect(supervisor.username == "alice")
        #expect(supervisor.email == "alice@example.com") // Lowercased
        #expect(supervisor.age == 30)
    }

    @Test("binding animation parameter is optional")
    func testBindingAnimationParameterOptional() async throws {
        let supervisor = Supervisor<FormFeature>(state: .init(), dependency: ())

        // Can omit animation parameter (defaults to nil)
        let binding1 = supervisor.binding(\.username, send: { .usernameChanged($0) })
        let binding2 = supervisor.directBinding(\.age)

        binding1.wrappedValue = "test"
        binding2.wrappedValue = 25

        #expect(supervisor.username == "test")
        #expect(supervisor.age == 25)
    }
}
