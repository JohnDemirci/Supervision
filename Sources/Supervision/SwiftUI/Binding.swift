//
//  Binding.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import SwiftUI

// MARK: - SwiftUI Binding Support

extension Supervisor {
    /// Creates a SwiftUI Binding that sends an action when the value changes
    ///
    /// This maintains unidirectional data flow by routing all changes through the action system.
    /// **Recommended for most use cases** where architecture purity is important.
    ///
    /// Supports SwiftUI transactions for preserving animations from gestures and animation modifiers.
    ///
    /// - Parameters:
    ///   - keyPath: KeyPath to the state property to bind
    ///   - action: Closure that creates an Action from the new value
    ///   - animation: Optional default animation to use when transaction has none
    /// - Returns: A transaction-aware Binding that reads from state and sends actions on write
    ///
    /// ## Example Usage
    /// ```swift
    /// struct UserFeature: FeatureProtocol {
    ///     struct State {
    ///         var name: String = ""
    ///         var email: String = ""
    ///         var age: Int = 0
    ///         var isEnabled: Bool = false
    ///     }
    ///
    ///     enum Action {
    ///         case nameChanged(String)
    ///         case emailChanged(String)
    ///         case ageChanged(Int)
    ///         case toggleEnabled(Bool)
    ///     }
    ///
    ///     func process(action: Action, context: borrowing Context<State>, dependency: Void) {
    ///         switch action {
    ///         case .nameChanged(let name):
    ///             context.mutate(\.name, to: name.trimmingCharacters(in: .whitespaces))
    ///
    ///         case .emailChanged(let email):
    ///             context.mutate(\.email, to: email.lowercased())
    ///
    ///         case .ageChanged(let age):
    ///             context.mutate(\.age, to: max(0, min(120, age)))
    ///
    ///         case .toggleEnabled(let enabled):
    ///             context.mutate(\.isEnabled, to: enabled)
    ///         }
    ///     }
    /// }
    ///
    /// struct UserView: View {
    ///     @State private var supervisor = Supervisor<UserFeature>(.init())
    ///
    ///     var body: some View {
    ///         Form {
    ///             // Basic binding (no animation)
    ///             TextField(
    ///                 "Name",
    ///                 text: supervisor.binding(\.name, send: { .nameChanged($0) })
    ///             )
    ///
    ///             // Binding with custom animation
    ///             Toggle(
    ///                 "Enabled",
    ///                 isOn: supervisor.binding(
    ///                     \.isEnabled,
    ///                     send: { .toggleEnabled($0) },
    ///                     animation: .spring(response: 0.3)
    ///                 )
    ///             )
    ///
    ///             // Animation modifier creates transaction automatically
    ///             Stepper(
    ///                 "Age: \(supervisor.state.age)",
    ///                 value: supervisor.binding(\.age, send: { .ageChanged($0) })
    ///             )
    ///             .animation(.easeInOut, value: supervisor.state.age)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// ## Transaction Support
    ///
    /// Bindings automatically receive `Transaction` from SwiftUI, which contains animation metadata:
    ///
    /// ```swift
    /// // SwiftUI passes transaction with spring animation
    /// Slider(value: binding)
    ///     .animation(.spring, value: state.value)
    ///
    /// // Gesture-driven changes include transaction
    /// DragGesture()
    ///     .onChanged { value in
    ///         binding.wrappedValue = value  // Transaction from gesture
    ///     }
    ///
    /// // Explicit animation creates transaction
    /// withAnimation(.easeInOut) {
    ///     binding.wrappedValue = newValue  // Transaction has easeInOut
    /// }
    /// ```
    ///
    /// **Animation Priority**:
    /// 1. Transaction's animation (from gesture, `.animation()`, or `withAnimation`)
    /// 2. Custom `animation` parameter passed to `binding()`
    /// 3. No animation (immediate update)
    ///
    /// ## Benefits
    /// - ✅ **Maintains unidirectional data flow**: All changes go through feature's process() method
    /// - ✅ **Preserves animations**: Gesture and modifier animations work correctly
    /// - ✅ **Enables validation**: Add validation logic in action handlers
    /// - ✅ **Supports side effects**: Trigger API calls, logging, analytics on state changes
    /// - ✅ **Fully testable**: Test actions without SwiftUI dependencies
    /// - ✅ **Debuggable**: Log all actions to trace state changes
    /// - ✅ **Type-safe**: Compiler ensures actions match value types
    ///
    /// ## Trade-offs
    /// - ⚠️ **Binding identity**: Binding is recreated on every view update (not cached)
    /// - ⚠️ **Verbosity**: Requires defining an action for each bindable property
    ///
    /// ## Animation Performance
    ///
    /// For most controls (TextField, Toggle, Picker), binding recreation doesn't affect animations.
    /// For continuous gesture-driven controls (Slider during drag), consider `directBinding(_:)`.
    ///
    /// ## Performance
    /// - **Getter**: Zero-copy read from state via KeyPath, O(1)
    /// - **Setter**: Routes through send() → process() → context.mutate()
    /// - **Animation**: Applied via `withAnimation()` or `withTransaction()`
    /// - **@Observable**: Ensures SwiftUI updates efficiently when state changes
    ///
    /// ## See Also
    /// - `directBinding(_:animation:)`: For cases where animation performance is critical
    public func binding<Value>(
        _ keyPath: KeyPath<State, Value>,
        send action: @escaping (Value) -> Action,
        animation: Animation? = nil
    ) -> Binding<Value> {
        Binding(
            get: {
                // Read current value from state
                // @Observable ensures view updates when state changes
                self.state[keyPath: keyPath]
            },
            set: { newValue, transaction in
                // Determine which animation to use
                // Priority: transaction.animation > custom animation > none
                let effectiveAnimation = transaction.animation ?? animation

                if let animation = effectiveAnimation {
                    // Apply animation when sending action
                    withAnimation(animation) {
                        self.send(action(newValue))
                    }
                } else {
                    // No animation - immediate update
                    self.send(action(newValue))
                }
            }
        )
    }

    /// Creates a SwiftUI Binding that directly mutates state without going through actions
    ///
    /// **⚠️ Use sparingly**: This bypasses the action system and directly mutates state.
    /// Only use when animation performance is critical or for purely presentational state.
    ///
    /// Supports SwiftUI transactions for smooth gesture-driven animations.
    ///
    /// - Parameters:
    ///   - keyPath: WritableKeyPath to the state property to bind
    ///   - animation: Optional default animation to use when transaction has none
    /// - Returns: A transaction-aware Binding that directly reads and writes to state
    ///
    /// ## When to Use
    ///
    /// **Good use cases** (presentational state):
    /// - Animated controls with gestures (Slider, drag gestures)
    /// - UI-only state (expanded/collapsed, selected tab)
    /// - Temporary input that's validated on submit
    /// - Continuous value updates (volume, brightness sliders)
    ///
    /// **Bad use cases** (business logic):
    /// - Form fields that need validation
    /// - State changes that trigger side effects
    /// - Values that affect business logic
    /// - State that should be logged/tracked
    ///
    /// ## Example Usage
    /// ```swift
    /// struct SettingsFeature: FeatureProtocol {
    ///     struct State {
    ///         var volume: Double = 50      // UI state - ok for direct binding
    ///         var brightness: Double = 75  // UI state - ok for direct binding
    ///         var username: String = ""    // Business logic - use action binding!
    ///     }
    ///
    ///     enum Action {
    ///         case usernameChanged(String)
    ///         case saveSettings
    ///         case volumeChangeCompleted(Double)
    ///     }
    ///
    ///     func process(action: Action, context: borrowing Context<State>, dependency: Void) {
    ///         switch action {
    ///         case .usernameChanged(let username):
    ///             context.mutate(\.username, to: username)
    ///
    ///         case .volumeChangeCompleted(let volume):
    ///             // Log final volume, trigger haptics, etc.
    ///             print("Volume set to: \(volume)")
    ///
    ///         case .saveSettings:
    ///             // Save all settings to server
    ///             // Volume was mutated directly via directBinding
    ///         }
    ///     }
    /// }
    ///
    /// struct SettingsView: View {
    ///     @State private var supervisor = Supervisor<SettingsFeature>(.init())
    ///
    ///     var body: some View {
    ///         Form {
    ///             // Direct binding with smooth spring animation
    ///             VStack {
    ///                 Text("Volume: \(Int(supervisor.state.volume))")
    ///                 Slider(
    ///                     value: supervisor.directBinding(\.volume, animation: .spring),
    ///                     in: 0...100,
    ///                     onEditingChanged: { editing in
    ///                         if !editing {
    ///                             // Send action when user finishes dragging
    ///                             supervisor.send(.volumeChangeCompleted(supervisor.state.volume))
    ///                         }
    ///                     }
    ///                 )
    ///             }
    ///
    ///             // Direct binding for brightness
    ///             VStack {
    ///                 Text("Brightness: \(Int(supervisor.state.brightness))")
    ///                 Slider(
    ///                     value: supervisor.directBinding(\.brightness),
    ///                     in: 0...100
    ///                 )
    ///                 .animation(.easeInOut, value: supervisor.state.brightness)
    ///             }
    ///
    ///             // Action binding for business logic
    ///             TextField(
    ///                 "Username",
    ///                 text: supervisor.binding(\.username, send: { .usernameChanged($0) })
    ///             )
    ///
    ///             Button("Save Settings") {
    ///                 supervisor.send(.saveSettings)
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// ## Transaction Support
    ///
    /// Direct bindings preserve gesture animations and modifier animations:
    ///
    /// ```swift
    /// // Gesture-driven animation preserved
    /// DragGesture()
    ///     .onChanged { value in
    ///         // Transaction from gesture includes animation
    ///         directBinding.wrappedValue = value.translation.height
    ///     }
    ///
    /// // Animation modifier creates transaction
    /// Slider(value: directBinding)
    ///     .animation(.spring, value: state.value)
    ///     // Spring animation applied to slider changes
    /// ```
    ///
    /// **Animation Priority**:
    /// 1. Transaction's animation (from gesture, `.animation()`, or `withAnimation`)
    /// 2. Custom `animation` parameter passed to `directBinding()`
    /// 3. No animation (immediate update)
    ///
    /// ## Benefits
    /// - ✅ **Smooth animations**: Transaction-aware for gesture-driven controls
    /// - ✅ **Stable identity**: Binding can be cached if needed
    /// - ✅ **Simple**: No need to define actions for UI-only state
    /// - ✅ **Performance**: Direct mutation is faster than action routing
    /// - ✅ **Animation control**: Can specify default animation
    ///
    /// ## Trade-offs
    /// - ⚠️ **Breaks unidirectional flow**: State changes don't go through feature logic
    /// - ⚠️ **No validation**: Can't validate or transform values on change
    /// - ⚠️ **No side effects**: Can't trigger API calls, logging, or other effects
    /// - ⚠️ **Harder to test**: Direct mutations bypass testable action system
    /// - ⚠️ **Less debuggable**: Changes aren't logged as actions
    ///
    /// ## Hybrid Pattern
    ///
    /// Use direct binding for smooth dragging, send action when complete:
    ///
    /// ```swift
    /// Slider(
    ///     value: supervisor.directBinding(\.volume, animation: .spring),
    ///     in: 0...100,
    ///     onEditingChanged: { editing in
    ///         if !editing {
    ///             // User finished dragging - send action for logging/side effects
    ///             supervisor.send(.volumeChangeCompleted(supervisor.state.volume))
    ///         }
    ///     }
    /// )
    /// ```
    ///
    /// ## Architecture Guidelines
    ///
    /// **Prefer `binding(_:send:animation:)` for**:
    /// - Business logic state
    /// - Values that need validation
    /// - State that triggers side effects
    /// - Anything you want to test or log
    ///
    /// **Use `directBinding(_:animation:)` for**:
    /// - Purely presentational state
    /// - Gesture-driven animated controls
    /// - Continuous value updates (sliders)
    /// - Temporary/transient state
    ///
    /// ## Performance
    /// - **Getter**: Zero-copy read from state via KeyPath, O(1)
    /// - **Setter**: Direct mutation, bypasses action system, O(1)
    /// - **Animation**: Applied via `withAnimation()` or `withTransaction()`
    /// - **@Observable**: Still triggers SwiftUI updates efficiently
    ///
    /// ## Important Notes
    /// - Direct mutations still trigger `@Observable` notifications
    /// - SwiftUI views will re-render when state changes
    /// - Reentrancy protection does NOT apply to direct mutations
    /// - Use judiciously - maintain architecture where it matters
    /// - Consider hybrid pattern: direct binding + completion action
    ///
    /// ## See Also
    /// - `binding(_:send:animation:)`: Recommended action-based binding for business logic
    public func directBinding<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        animation: Animation? = nil
    ) -> Binding<Value> {
        Binding(
            get: {
                // Read current value from state
                self.state[keyPath: keyPath]
            },
            set: { newValue, transaction in
                // Determine which animation to use
                // Priority: transaction.animation > custom animation > none
                let effectiveAnimation = transaction.animation ?? animation

                if let animation = effectiveAnimation {
                    // Apply animation when mutating state
                    withAnimation(animation) {
                        self.state[keyPath: keyPath] = newValue
                    }
                } else {
                    // No animation - immediate update
                    self.state[keyPath: keyPath] = newValue
                }
            }
        )
    }
}
