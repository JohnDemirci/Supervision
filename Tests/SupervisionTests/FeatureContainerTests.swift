//
//  FeatureContainerTests.swift
//  Supervision
//
//  Created by John on 4/20/26.
//

import Testing
@testable import Supervision

@MainActor
struct FeatureContainerTests {
    @Test
    func `two counter features are equal to each other`() {
        let container = FeatureContainer(dependency: ())
        
        let counterFeature1 = container.feature(
            type: CounterFeature.self,
            state: CounterFeature.State()
        )
        
        let counterFeature2 = container.feature(
            type: CounterFeature.self,
            state: CounterFeature.State()
        )
        
        #expect(counterFeature1 == counterFeature2)
        #expect(counterFeature2 === counterFeature1)
    }
    
    @Test
    func `container contains the features and compositions together`() async throws {
        let container = FeatureContainer(dependency: ())
        let counterFeature = container.feature(
            type: CounterFeature.self,
            state: CounterFeature.State()
        )
        
        let toggleFeature = container.feature(
            type: ToggleFeature.self,
            state: ToggleFeature.State()
        )
        
        let _: ComposedFeature<DashboardComposition> = container.composedFeature(
            composed: DashboardComposition(
                parents: ParentFeatures(counterFeature, toggleFeature)
            )
        )
        
        #expect(container.count == 3)
    }

    @Test
    func `testing container returns the injected feature`() {
        let injected = Feature<CounterFeature>(state: .init())
        let container = TestingFeatureContainer<Void>(features: [injected])

        let resolved = container.feature(
            type: CounterFeature.self,
            state: .init(counter: 100)
        )

        #expect(resolved === injected)
        #expect(resolved.state.counter == 0)
    }

    @Test
    func `testing container does not evaluate the dependency closure`() {
        let injected = Feature<TodoFeature>.makePreview(
            state: .init(todos: ["Preview todo"]),
            previewActionMapper: nil
        )
        let container = TestingFeatureContainer<Void>(features: [injected])

        let resolved = container.feature(
            type: TodoFeature.self,
            state: .init()
        ) { _ in
            Issue.record("The testing container evaluated a dependency closure")
            return .init(client: TodoClient())
        }

        #expect(resolved === injected)
        #expect(resolved.state.todos == ["Preview todo"])
    }

    @Test
    func `test factory returns the container abstraction`() {
        let injected = Feature<CounterFeature>(state: .init(counter: 42))
        let container: any ContainerManagement<Void> = TestingFeatureContainer<Void>.test(
            features: [injected]
        )

        let resolved = container.feature(
            type: CounterFeature.self,
            state: .init()
        )

        #expect(resolved === injected)
    }
}
