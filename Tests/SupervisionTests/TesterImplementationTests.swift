//
//  TesterImplementationTests.swift
//  Supervision
//
//  Created by John on 1/16/26.
//

import Testing
import Supervision

@Suite("Tester implementation from the view of users")
struct TesterImplementationTests {
    @Test
    func fetchingDogsSuccess() async throws {
        let tester = Tester<AnimalFeature>(
            state: Tester<AnimalFeature>.State()
        )
        
        tester.send(.fetchDogs) { currentState, asserter in
            #expect(currentState.dogs == [])
            asserter.assertRun()
        }
    }
}


private struct AnimalFeature: FeatureProtocol {
    struct State: Equatable {
        var dogs: [String] = []
        var cats: [String] = []
    }
    
    enum Action {
        case fetchDogs
        case fetchCats
        case fetchDogsResult(Result<[String], Error>)
        case fetchCatsResult(Result<[String], Error>)
    }
    
    struct Dependency {
        let client: AnimalClient = .init()
    }
    
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .fetchCats:
            return .run {
                try await $0.client.fetchCats()
            } map: { result in
                .fetchCatsResult(result)
            }
            
        case .fetchDogs:
            return .run {
                try await $0.client.fetchDogs()
            } map: { result in
                .fetchDogsResult(result)
            }
            
        case .fetchCatsResult(let result):
            guard case let .success(cats) = result else {
                return .done
            }
            
            context.modify(\.cats, to: cats)
            return .done
            
        case .fetchDogsResult(let result):
            guard case let .success(dogs) = result else {
                return .done
            }
            
            context.modify(\.dogs, to: dogs)
            return .done
        }
    }
}

final class AnimalClient: Sendable {
    init() {}
    
    func fetchDogs() async throws -> [String] {
        return [
            .goldenRetriever, .beagle, .dalmatian
        ]
    }
    
    func fetchCats() async throws -> [String] {
        return [.persion, .ragdoll, .siamese]
    }
}

extension String {
    static let goldenRetriever = "Golden Retriever"
    static let frenchBlueHeeler = "French Blue Heeler"
    static let dalmatian = "Dalmatian"
    static let beagle = "Beagle"
    static let husky = "Husky"
    
    static let persion = "Persion"
    static let ragdoll = "Ragdoll"
    static let siamese = "Siamese"
}
