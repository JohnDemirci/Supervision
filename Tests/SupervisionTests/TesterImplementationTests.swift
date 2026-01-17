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
        
        let fetchDogsWork = tester.send(.fetchDogs) { currentState  in
            #expect(currentState.dogs == [])
        }
        .assertRun()

        try tester.feedResult(for: fetchDogsWork, result: .success(["one", "two"])) { state in
            #expect(state.dogs == ["one", "two"])
        }
        .assertDone()
    }

    @Test
    func fetchingDogsCancellation() async throws {
        let tester = Tester<AnimalFeature>(
            state: Tester<AnimalFeature>.State()
        )

        tester.send(.fetchDogs) { currentState  in
            #expect(currentState.dogs == [])
        }
        .assertRun()

        tester.send(.cancel(.dogs))
            .assertCancel(AnimalFeature.CancelID.dogs)

        #expect(tester.dogs.isEmpty)
    }

    @Test
    func fetchConcatenate() async throws {
        let tester = Tester<AnimalFeature>(
            state: Tester<AnimalFeature>.State()
        )

        let concationationWork = tester.send(.fetchAllConcatenate)
            .assertConcatenate(2)

        let (fetchDogWork, fetchCatWork) = try concationationWork.subInspections()

        fetchDogWork.assertRun()
        fetchCatWork.assertRun()

        try tester.feedResult(for: fetchDogWork, result: .success(["dog1", "dog2"])) { state in
            #expect(state.dogs == ["dog1", "dog2"])
        }
        .assertDone()

        try tester.feedResult(for: fetchCatWork, result: .success(["cat1", "cat2"])) { state in
            #expect(state.cats == ["cat1", "cat2"])
        }
        .assertDone()
    }
    
    @Test
    func nestedConcatanate() async throws {
        let tester = Tester<AnimalFeature>(
            state: Tester<AnimalFeature>.State()
        )
        
        let parent = tester.send(.nestedConcatenate)
            .assertConcatenate(2)

        let (child1, child2) = try parent.subInspections()

        child1
            .assertConcatenate(2)
        child2
            .assertConcatenate(3)

        let (grandChild1, grandChild2) = try child1.subInspections()

        grandChild1.assertRun()
        grandChild2.assertRun()

        try tester.feedResult(for: grandChild1, result: .success(["dog1"])) { state in
            #expect(state.dogs == ["dog1"])
        }
        .assertDone()
        
        try tester.feedResult(for: grandChild2, result: .success(["cat1"])) { state in
            #expect(state.cats == ["cat1"])
        }
        .assertDone()

        let (grandChild3, grandChild4, grandChild5) = try child2.subInspections()

        grandChild3.assertRun()
        grandChild4.assertRun()
        grandChild5.assertConcatenate(2)
        
        try tester.feedResult(for: grandChild3, result: .success(["dog2"])) { state in
            #expect(state.dogs == ["dog2"])
        }
        .assertDone()
        
        try tester.feedResult(for: grandChild4, result: .success(["cat2"])) { state in
            #expect(state.cats == ["cat2"])
        }
        .assertDone()

        let (greatGrandChild1, greatGrandChild2) = try grandChild5.subInspections()

        greatGrandChild1.assertRun()
        greatGrandChild2.assertRun()

        try tester.feedResult(for: greatGrandChild1, result: .success(["dog4"])) { state in
            #expect(state.dogs == ["dog4"])
        }
        .assertDone()
        
        try tester.feedResult(for: greatGrandChild2, result: .success(["cat4"])) { state in
            #expect(state.cats == ["cat4"])
        }
        .assertDone()
    }
    
    @Test
    func concataneteWithDifferentOrders() async throws {
        let tester = Tester<AnimalFeature>(
            state: Tester<AnimalFeature>.State()
        )
        
        let concatenateWork = tester.send(.fetchAllConcatenate)
            .assertConcatenate(2)

        let (run1, run2) = try concatenateWork.subInspections()

        try tester.feedResult(for: run1, result: .success(["dog1"])) { state in
            #expect(state.dogs == ["dog1"])
        }
        .assertDone()

        try tester.feedResult(for: run2, result: .success(["cat1"])) { state in
            #expect(state.cats == ["cat1"])
        }
        .assertDone()
    }

    @Test
    func testingMergeFetch() async throws {
        let tester = Tester<AnimalFeature>(
            state: Tester<AnimalFeature>.State()
        )

        let mergeWork = tester.send(.mergeFetch)
            .assertMerge(3, swaps: (0, 2))

        let (peopleFetchWork, catFetchWork, dogFetchWork) = try mergeWork.subInspections()

        try tester.feedResult(for: peopleFetchWork, result: .success(["john"])) { state in
            #expect(state.people == ["john"])
        }
        .assertDone()

        try tester.feedResult(for: catFetchWork, result: .success(["ragdoll"])) { state in
            #expect(state.cats == ["ragdoll"])
        }
        .assertDone()

        try tester.feedResult(for: dogFetchWork, result: .success(["golden"])) { state in
            #expect(state.dogs == ["golden"])
        }
        .assertDone()
    }
}


private struct AnimalFeature: FeatureProtocol {
    struct State: Equatable {
        var dogs: [String] = []
        var cats: [String] = []
        var people: [String] = []
    }

    enum CancelID: Hashable, Sendable {
        case dogs
        case cats
    }

    enum Action {
        case cancel(CancelID)
        case fetchAllConcatenate
        case nestedConcatenate
        case fetchDogs
        case fetchCats
        case mergeFetch
        case fetchDogsResult(Result<[String], Error>)
        case fetchCatsResult(Result<[String], Error>)
        case fetchPeopleResult(Result<[String], Error>)
    }
    
    struct Dependency {
        let client: AnimalClient = .init()
    }
    
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .cancel(let cancelID):
            return .cancel(cancelID)

        case .mergeFetch:
            return .merge(
                .run(
                    body: { try await $0.client.fetchDogs() },
                    map: { .fetchDogsResult($0) }
                ),
                .run(
                    body: { try await $0.client.fetchCats() },
                    map: { .fetchCatsResult($0) }
                ),
                .run(
                    body: { try await $0.client.fetchPeople() },
                    map: { .fetchPeopleResult($0) }
                )
            )

        case .fetchAllConcatenate:
            return .concatenate(
                .run(
                    body: { try await $0.client.fetchDogs() },
                    map: { .fetchDogsResult($0) }
                ),
                .run(
                    body: { try await $0.client.fetchCats() },
                    map: { .fetchCatsResult($0) }
                )
            )

        case .fetchPeopleResult(let result):
            if case .success(let newPeople) = result {
                context.modify(\.people, to: newPeople)
            }
            return .done

        case .nestedConcatenate:
            return .concatenate(
                .concatenate(
                    .run(
                        body: { try await $0.client.fetchDogs() },
                        map: { .fetchDogsResult($0) }
                    ),
                    .run(
                        body: { try await $0.client.fetchCats() },
                        map: { .fetchCatsResult($0) }
                    )
                ),
                .concatenate(
                    .run(
                        body: { try await $0.client.fetchDogs() },
                        map: { .fetchDogsResult($0) }
                    ),
                    .run(
                        body: { try await $0.client.fetchCats() },
                        map: { .fetchCatsResult($0) }
                    ),
                    .concatenate(
                        .run(
                            body: { try await $0.client.fetchDogs() },
                            map: { .fetchDogsResult($0) }
                        ),
                        .run(
                            body: { try await $0.client.fetchCats() },
                            map: { .fetchCatsResult($0) }
                        )
                    )
                )
            )

        case .fetchCats:
            return .run {
                try await $0.client.fetchCats()
            } map: { result in
                .fetchCatsResult(result)
            }
            .cancellable(id: CancelID.cats)

        case .fetchDogs:
            return .run {
                try await $0.client.fetchDogs()
            } map: { result in
                .fetchDogsResult(result)
            }
            .cancellable(id: CancelID.dogs)

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

    func fetchPeople() async throws -> [String] {
        return ["John", "Jane", "Alice"]
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
