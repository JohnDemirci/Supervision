//
//  SharedTests.swift
//  Supervision
//
//  Created by John on 4/20/26.
//

import Testing
@testable import Supervision

private struct CussFeature: FeatureBlueprint {
    @ObservableValue
    struct State {
        let counter: Shared<CounterFeature, Int>
        
        init(counter: Shared<CounterFeature, Int>) {
            self.counter = counter
        }
    }
    
    typealias Action = Void
    typealias Dependency = Void
    
    func process(action: Void, context: borrowing Context<State>) -> FeatureWork {
        .done
    }
}

@MainActor
struct SharedTests {
    @Test
    func `shated property projects the value`() async throws {
        let counterFeature = Feature<CounterFeature>.init(
            state: CounterFeature.State(),
            dependency: ()
        )
        
        let cussFeature = Feature<CussFeature>.init(
            state: CussFeature.State(
                counter: Shared(
                    feature: counterFeature,
                    keypath: \.counter
                )
            ),
            dependency: ()
        )
        
        counterFeature.send(.increment)
        
        await Task.megaYield()
        
        #expect(cussFeature.counter.value == 1)
    }
}
