//
//  BatchBuilderExample.swift
//  Supervision
//
//  Example demonstrating the ergonomic batch API
//

import Supervision

// MARK: - Example Feature

struct UserManagementFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State {
        var user: User = User()
        var profile: Profile = Profile()
        var settings: Settings = Settings()

        struct User {
            var id: String = ""
            var username: String = ""
            var email: String = ""
            var isActive: Bool = false
        }

        struct Profile {
            var firstName: String = ""
            var lastName: String = ""
            var age: Int = 0
            var bio: String = ""
            var avatar: String = ""
        }

        struct Settings {
            var notifications: Bool = true
            var darkMode: Bool = false
            var language: String = "en"
        }
    }

    enum Action {
        case createUser(id: String, username: String, email: String)
        case updateProfile(firstName: String, lastName: String, age: Int, bio: String)
        case updateSettings(notifications: Bool, darkMode: Bool, language: String)
        case completeOnboarding(
            id: String,
            username: String,
            email: String,
            firstName: String,
            lastName: String,
            age: Int
        )
    }

    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        switch action {
        case .createUser(let id, let username, let email):
            // Example 1: Simple batch with top-level nested properties
            context.batch { state in
                state.user.id.wrappedValue = id
                state.user.username.wrappedValue = username
                state.user.email.wrappedValue = email
                state.user.isActive.wrappedValue = true
            }
            // All 4 mutations trigger only ONE @Observable notification

        case .updateProfile(let firstName, let lastName, let age, let bio):
            // Example 2: Batch updates to nested struct
            context.batch { state in
                state.profile.firstName.wrappedValue = firstName
                state.profile.lastName.wrappedValue = lastName
                state.profile.age.wrappedValue = age
                state.profile.bio.wrappedValue = bio
            }

        case .updateSettings(let notifications, let darkMode, let language):
            // Example 3: Boolean and String mutations
            context.batch { state in
                state.settings.notifications.wrappedValue = notifications
                state.settings.darkMode.wrappedValue = darkMode
                state.settings.language.wrappedValue = language
            }

        case .completeOnboarding(let id, let username, let email, let firstName, let lastName, let age):
            // Example 4: Large batch across multiple nested structs
            // This demonstrates the power of batching: 7 mutations, 1 notification
            context.batch { state in
                // User fields
                state.user.id.wrappedValue = id
                state.user.username.wrappedValue = username
                state.user.email.wrappedValue = email
                state.user.isActive.wrappedValue = true

                // Profile fields
                state.profile.firstName.wrappedValue = firstName
                state.profile.lastName.wrappedValue = lastName
                state.profile.age.wrappedValue = age
            }
        }
    }
}

// MARK: - Usage Examples

@MainActor
func examples() {
    let supervisor = Supervisor<UserManagementFeature>(UserManagementFeature.State())

    // Example 1: Create a new user
    supervisor.send(.createUser(
        id: "user123",
        username: "johndoe",
        email: "john@example.com"
    ))

    print("User created:")
    print("  ID: \(supervisor.state.user.id)")
    print("  Username: \(supervisor.state.user.username)")
    print("  Email: \(supervisor.state.user.email)")
    print("  Active: \(supervisor.state.user.isActive)")

    // Example 2: Update profile
    supervisor.send(.updateProfile(
        firstName: "John",
        lastName: "Doe",
        age: 30,
        bio: "Swift enthusiast"
    ))

    print("\nProfile updated:")
    print("  Name: \(supervisor.state.profile.firstName) \(supervisor.state.profile.lastName)")
    print("  Age: \(supervisor.state.profile.age)")
    print("  Bio: \(supervisor.state.profile.bio)")

    // Example 3: Complete onboarding with one batched operation
    let supervisor2 = Supervisor<UserManagementFeature>(UserManagementFeature.State())

    supervisor2.send(.completeOnboarding(
        id: "user456",
        username: "janedoe",
        email: "jane@example.com",
        firstName: "Jane",
        lastName: "Doe",
        age: 28
    ))

    print("\nOnboarding completed:")
    print("  User: \(supervisor2.state.user.username) (\(supervisor2.state.user.email))")
    print("  Profile: \(supervisor2.state.profile.firstName) \(supervisor2.state.profile.lastName), age \(supervisor2.state.profile.age)")
}

// MARK: - Comparison: Old vs New API

struct ComparisonFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State {
        var a: Int = 0
        var b: String = ""
        var c: Bool = false
        var d: Double = 0.0
    }

    enum Action {
        case updateAllOldWay
        case updateAllNewWay
    }

    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        switch action {
        case .updateAllOldWay:
            // OLD: Verbose, requires explicit keyPath syntax
            context.batch {
                context.mutate(\.a, to: 42)
                context.mutate(\.b, to: "hello")
                context.mutate(\.c, to: true)
                context.mutate(\.d, to: 3.14)
            }

        case .updateAllNewWay:
            // NEW: Ergonomic, property-like syntax
            context.batch { state in
                state.a.wrappedValue = 42
                state.b.wrappedValue = "hello"
                state.c.wrappedValue = true
                state.d.wrappedValue = 3.14
            }
        }
    }
}

// MARK: - Safety Demonstration

// This code DOES NOT COMPILE (as intended):
/*
struct UnsafeFeature: FeatureProtocol {
    struct State {
        var value: Int = 0
    }

    enum Action {
        case tryToEscape
    }

    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        var escapedBuilder: BatchBuilder<State>? = nil

        context.batch { state in
            // ERROR: Cannot assign value of type 'BatchBuilder<State>' to type 'BatchBuilder<State>?'
            // ~Copyable types cannot be stored or copied
            // escapedBuilder = state
        }

        // This prevents the builder from escaping the batch closure
        // Compile-time safety!
    }
}
*/

// MARK: - Performance Notes

/*
 Performance comparison:

 Without batching:
 ```swift
 context.mutate(\.a, to: 1)  // @Observable notification #1
 context.mutate(\.b, to: 2)  // @Observable notification #2
 context.mutate(\.c, to: 3)  // @Observable notification #3
 // Total: 3 notifications, potentially 3 UI re-renders
 ```

 With old batch API:
 ```swift
 context.batch {
     context.mutate(\.a, to: 1)
     context.mutate(\.b, to: 2)
     context.mutate(\.c, to: 3)
 }
 // Total: 1 notification, 1 UI re-render
 ```

 With new batch API (same performance, better ergonomics):
 ```swift
 context.batch { state in
     state.a.wrappedValue = 1
     state.b.wrappedValue = 2
     state.c.wrappedValue = 3
 }
 // Total: 1 notification, 1 UI re-render
 ```
*/
