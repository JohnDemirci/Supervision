//
//  CompositionTests.swift
//  Supervision
//
//  Created by John on 4/20/26.
//

import Testing
@testable import Supervision

@MainActor
struct CompositionTests {
    @Test
    func `changes in onr changes the composition`() async throws {
        let counterFeature = Feature<CounterFeature>(
            state: CounterFeature.State(),
            dependency: ()
        )
        
        let toggleFeature = Feature<ToggleFeature>(
            state: ToggleFeature.State(),
            dependency: ()
        )
        
        let dashboard = ComposedFeature(
            composed: DashboardComposition(
                parents: .init(counterFeature, toggleFeature)
            )
        )
        
        counterFeature.send(.increment)
        
        await Task.megaYield()
        
        #expect(dashboard.count == 1)
    }
    
    @Test
    func `dashboard actions mapped to parent features and changes are observed`() async throws {
        let counterFeature = Feature<CounterFeature>(
            state: CounterFeature.State(),
            dependency: ()
        )
        
        let toggleFeature = Feature<ToggleFeature>(
            state: ToggleFeature.State(),
            dependency: ()
        )
        
        let dashboard = ComposedFeature(
            composed: DashboardComposition(
                parents: .init(counterFeature, toggleFeature)
            )
        )
        
        dashboard.send(.increment)
        dashboard.send(.increment)
        
        await Task.megaYield()
        
        #expect(counterFeature.counter == 2)
    }
}

extension Task where Success == Never, Failure == Never {
    static func megaYield(count: Int = 20) async {
        for _ in 0..<count {
            await Task<Void, Never>.detached(priority: .background) { await Task.yield() }.value
        }
    }
}
