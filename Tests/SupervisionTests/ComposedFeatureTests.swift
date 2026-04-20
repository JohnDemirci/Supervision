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
            case decrement
        }

        typealias State = CounterState
        typealias Dependency = Void

        func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
            switch action {
            case .increment:
                context.state.count += 1
            case .decrement:
                context.state.count -= 1
            }

            return .done
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
            case .setEnabled(let value):
                context.state.isEnabled = value
            }

            return .done
        }
    }

    @ObservableValue
    struct TitleState: Equatable {
        var title = ""
    }

    private struct TitleFeature: FeatureBlueprint {
        enum Action: Sendable {
            case setTitle(String)
        }

        typealias State = TitleState
        typealias Dependency = Void

        func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
            switch action {
            case .setTitle(let title):
                context.state.title = title
            }

            return .done
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

    private struct DashboardComposition: Composed {
        enum Action: Sendable {
            case increment
            case setEnabled(Bool)
            case synchronize
        }

        typealias State = DashboardState
        typealias Parents = ParentFeatures<CounterFeature, ToggleFeature>

        let parents: Parents

        func mapAction(_ action: Action) -> Parents.Actions {
            switch action {
            case .increment:
                (.increment, nil)
            case .setEnabled(let isEnabled):
                (nil, .setEnabled(isEnabled))
            case .synchronize:
                (.increment, .setEnabled(true))
            }
        }

        func mapState() -> State {
            parents.withFeatures { counter, toggle in
                DashboardState(
                    count: counter.count,
                    isEnabled: toggle.isEnabled
                )
            }
        }

        func updateState(_ state: inout State) {
            parents.withFeatures { counter, toggle in
                state.count = counter.count
                state.isEnabled = toggle.isEnabled
            }
        }
    }

    @ObservableValue
    struct SummaryState: Equatable {
        var count: Int
        var isEnabled: Bool
        var title: String

        init(
            count: Int,
            isEnabled: Bool,
            title: String
        ) {
            self.count = count
            self.isEnabled = isEnabled
            self.title = title
        }

        static func == (lhs: SummaryState, rhs: SummaryState) -> Bool {
            lhs.count == rhs.count &&
            lhs.isEnabled == rhs.isEnabled &&
            lhs.title == rhs.title
        }
    }

    private struct SummaryComposition: Composed {
        enum Action: Sendable {
            case synchronize
            case setTitle(String)
        }

        typealias State = SummaryState
        typealias Parents = ParentFeatures<CounterFeature, ToggleFeature, TitleFeature>

        let parents: Parents

        func mapAction(_ action: Action) -> Parents.Actions {
            switch action {
            case .synchronize:
                (.increment, .setEnabled(true), .setTitle("Synced"))
            case .setTitle(let title):
                (nil, nil, .setTitle(title))
            }
        }

        func mapState() -> State {
            parents.withFeatures { counter, toggle, title in
                SummaryState(
                    count: counter.count,
                    isEnabled: toggle.isEnabled,
                    title: title.title
                )
            }
        }

        func updateState(_ state: inout State) {
            parents.withFeatures { counter, toggle, title in
                state.count = counter.count
                state.isEnabled = toggle.isEnabled
                state.title = title.title
            }
        }
    }

    @MainActor
    private func makeDashboard() -> (
        counter: Feature<CounterFeature>,
        toggle: Feature<ToggleFeature>,
        composed: ComposedFeature<DashboardComposition>
    ) {
        let counter = Feature<CounterFeature>(state: .init())
        let toggle = Feature<ToggleFeature>(state: .init())
        let composed = ComposedFeature(
            composed: DashboardComposition(
                parents: ParentFeatures(counter, toggle)
            )
        )

        return (counter, toggle, composed)
    }

    @MainActor
    private func makeSummary() -> (
        counter: Feature<CounterFeature>,
        toggle: Feature<ToggleFeature>,
        title: Feature<TitleFeature>,
        composed: ComposedFeature<SummaryComposition>
    ) {
        let counter = Feature<CounterFeature>(state: .init())
        let toggle = Feature<ToggleFeature>(state: .init())
        let title = Feature<TitleFeature>(state: .init())
        let composed = ComposedFeature(
            composed: SummaryComposition(
                parents: ParentFeatures(counter, toggle, title)
            )
        )

        return (counter, toggle, title, composed)
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
    func mappedActionsFanOutToParentFeatures() async {
        let (counter, toggle, composed) = makeDashboard()

        #expect(
            composed.state == DashboardState(
                count: 0,
                isEnabled: false
            )
        )

        composed.send(DashboardComposition.Action.synchronize)

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
    func parentMutationRefreshesDerivedState() async {
        let (counter, toggle, composed) = makeDashboard()

        counter.send(CounterFeature.Action.increment)
        toggle.send(ToggleFeature.Action.setEnabled(true))

        await settle {
            composed.state == DashboardState(count: 1, isEnabled: true)
        }

        #expect(composed.count == 1)
        #expect(composed.isEnabled == true)
    }

    @Test
    @MainActor
    func parameterPackParentsSupportThreeFeatures() async {
        let (counter, toggle, title, composed) = makeSummary()

        composed.send(SummaryComposition.Action.synchronize)

        await settle {
            counter.state.count == 1 &&
            toggle.state.isEnabled &&
            title.state.title == "Synced" &&
            composed.state == SummaryState(
                count: 1,
                isEnabled: true,
                title: "Synced"
            )
        }

        #expect(counter.state.count == 1)
        #expect(toggle.state.isEnabled == true)
        #expect(title.state.title == "Synced")
        #expect(
            composed.state == SummaryState(
                count: 1,
                isEnabled: true,
                title: "Synced"
            )
        )
    }
}
