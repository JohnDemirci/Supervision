import Testing
@testable import Supervision

@Suite("Composed feature")
struct ComposedFeatureTests {
    @ObservableValue
    struct CounterState: Equatable {
        var count = 0
    }

    private struct CounterFeature: FeatureBlueprint {
        enum Action: Sendable {
            case increment
        }

        typealias State = CounterState
        typealias Dependency = Void

        func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
            switch action {
            case .increment:
                context.state.count += 1
                return .done
            }
        }
    }

    @ObservableValue
    struct ToggleState: Equatable {
        var isEnabled = false
    }

    private struct ToggleFeature: FeatureBlueprint {
        enum Action: Sendable {
            case setEnabled(Bool)
        }

        typealias State = ToggleState
        typealias Dependency = Void

        func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
            switch action {
            case .setEnabled(let isEnabled):
                context.state.isEnabled = isEnabled
                return .done
            }
        }
    }

    @ObservableValue
    struct DashboardState: Equatable {
        var count: Int
        var isEnabled: Bool

        init(
            count: Int,
            isEnabled: Bool
        ) {
            self.count = count
            self.isEnabled = isEnabled
        }

        static func == (lhs: DashboardState, rhs: DashboardState) -> Bool {
            lhs.count == rhs.count &&
            lhs.isEnabled == rhs.isEnabled
        }
    }

    private enum DashboardAction: Sendable {
        case increment
        case setEnabled(Bool)
        case synchronize
    }

    private var dashboardBlueprint: ComposedBlueprint<
        DashboardState,
        DashboardAction,
        (CounterFeature.State, ToggleFeature.State),
        (CounterFeature.Action?, ToggleFeature.Action?)
    > {
        ComposedBlueprint(
            send: { action in
                switch action {
                case .increment:
                    (.increment, nil)
                case .setEnabled(let isEnabled):
                    (nil, .setEnabled(isEnabled))
                case .synchronize:
                    (.increment, .setEnabled(true))
                }
            },
            mapValue: { values in
                let (counterState, toggleState) = values
                return DashboardState(
                    count: counterState.count,
                    isEnabled: toggleState.isEnabled
                )
            }
        )
    }

    @MainActor
    private func makeFeatures() -> (
        counter: Feature<CounterFeature>,
        toggle: Feature<ToggleFeature>,
        composed: ComposedFeature<DashboardState, DashboardAction>
    ) {
        let counter = Feature<CounterFeature>(state: .init())
        let toggle = Feature<ToggleFeature>(state: .init())
        let composed = Composed.of(counter, toggle).composedBy(dashboardBlueprint)

        return (counter, toggle, composed)
    }

    @MainActor
    private func settle(
        until condition: @escaping @MainActor () -> Bool,
        iterations: Int = 50
    ) async {
        for _ in 0..<iterations {
            if condition() {
                return
            }

            await Task.yield()
        }
    }

    @Test
    @MainActor
    func blueprintFansOutMappedActions() async {
        let (counter, toggle, composed) = makeFeatures()

        #expect(
            composed.state == DashboardState(
                count: 0,
                isEnabled: false
            )
        )

        composed.send(.synchronize)

        await settle {
            counter.state.count == 1 &&
            toggle.state.isEnabled &&
            composed.state == DashboardState(count: 1, isEnabled: true)
        }

        #expect(counter.state.count == 1)
        #expect(toggle.state.isEnabled == true)
        #expect(composed.state == DashboardState(count: 1, isEnabled: true))
    }

    @Test
    @MainActor
    func childFeatureChangesRefreshDerivedState() async {
        let (counter, toggle, composed) = makeFeatures()

        counter.send(.increment)
        toggle.send(.setEnabled(true))

        await settle {
            composed.state == DashboardState(count: 1, isEnabled: true)
        }

        #expect(composed.count == 1)
        #expect(composed.isEnabled == true)
    }

    @Test
    @MainActor
    func closureComposedByOverloadBuildsAndRoutesActions() async {
        let counter = Feature<CounterFeature>(state: .init())
        let toggle = Feature<ToggleFeature>(state: .init())

        let composed = Composed.of(counter, toggle).composedBy(
            send: { (action: DashboardAction) in
                switch action {
                case .increment:
                    (.increment, nil)
                case .setEnabled(let isEnabled):
                    (nil, .setEnabled(isEnabled))
                case .synchronize:
                    (.increment, .setEnabled(true))
                }
            },
            mapValue: { (counterState: CounterFeature.State, toggleState: ToggleFeature.State) in
                DashboardState(
                    count: counterState.count,
                    isEnabled: toggleState.isEnabled
                )
            }
        )

        composed.send(.increment)

        await settle {
            counter.state.count == 1 &&
            toggle.state.isEnabled == false &&
            composed.state == DashboardState(count: 1, isEnabled: false)
        }

        #expect(counter.state.count == 1)
        #expect(toggle.state.isEnabled == false)
        #expect(composed.state == DashboardState(count: 1, isEnabled: false))
    }

    @Test
    @MainActor
    func nilMappedActionDoesNotForwardToOtherParent() async {
        let (counter, toggle, composed) = makeFeatures()

        composed.send(.increment)

        await settle {
            counter.state.count == 1 &&
            toggle.state.isEnabled == false
        }

        #expect(counter.state.count == 1)
        #expect(toggle.state.isEnabled == false)
        #expect(composed.state == DashboardState(count: 1, isEnabled: false))
    }

    @Test
    @MainActor
    func singleParentMutationRecomputesDerivedState() async {
        let (counter, _, composed) = makeFeatures()

        counter.send(.increment)

        await settle {
            composed.state == DashboardState(count: 1, isEnabled: false)
        }

        #expect(composed.state == DashboardState(count: 1, isEnabled: false))
    }
}
