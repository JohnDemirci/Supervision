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
}
