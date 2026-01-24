//
//  FeatureContainerTests.swift
//  Supervision
//
//  Created by John on 11/28/25.
//

import Testing
@testable import Supervision

// MARK: - Test Dependencies

struct AppDependency {
    let userClient: UserClient = .init()
}

final class UserClient: Sendable {}

struct UserFeature: FeatureBlueprint {
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        switch action {
        case .changeName(let newName):
            context.modify(\.name, to: newName)
            return .done
        }
    }

    struct Dependency: Sendable {
        let client: UserClient
    }

    struct State: Equatable {
        var name: String = "something"
    }

    enum Action {
        case changeName(String)
    }
}

struct DeviceFeature: FeatureBlueprint {
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        return .done
    }

    struct Dependency: Sendable {
        let client: UserClient
    }

    struct State: Identifiable, Equatable {
        let id: String
        var devices: [String] = []
    }

    enum Action {
        case nothing
    }
}

struct VoidFeature: FeatureBlueprint {
    typealias Dependency = Void

    struct State: Equatable {}

    enum Action {
        case nothing
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        return .done
    }
}

struct IdentifiableVoidFeature: FeatureBlueprint {
    typealias Dependency = Void
    
    struct State: Identifiable, Equatable {
        let id: String
    }
    
    enum Action {
        case nothing
    }
    
    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        return .done
    }
}

@MainActor
@Suite("FeatureContainer")
struct FeatureContainerTests {
    @Test func identicalfeatures() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let userfeature: Feature<UserFeature> = FeatureContainer.feature(
            state: UserFeature.State()) {
                UserFeature.Dependency(client: $0.userClient)
            }
        
        let anotherfeature: Feature<UserFeature> = FeatureContainer.feature(
            state: UserFeature.State()) {
                UserFeature.Dependency(client: $0.userClient)
            }
        
        #expect(userfeature === anotherfeature)

        #expect(FeatureContainer.numberOffeatures == 1)
    }
    
    @Test
    func identicalIndetifiablefeaturesReturnsTheSamefeature() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let deviceState1 = DeviceFeature.State(id: "1")
        let devicefeature: Feature<DeviceFeature> = FeatureContainer.feature(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        let devicefeature2: Feature<DeviceFeature> = FeatureContainer.feature(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        #expect(devicefeature === devicefeature2)
    }
    
    @Test func multiplefeaturesWithDifferentIdentities() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let deviceState1 = DeviceFeature.State(id: "1")
        let devicefeature: Feature<DeviceFeature> = FeatureContainer.feature(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        let deviceState2 = DeviceFeature.State(id: "2")
        let devicefeature2: Feature<DeviceFeature> = FeatureContainer.feature(
            state: deviceState2) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        // Verify that different identities create different features
        #expect(devicefeature !== devicefeature2)
        #expect(FeatureContainer.numberOffeatures == 2)
    }
    
    @Test func voidDependency() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let void1: Feature<VoidFeature> = FeatureContainer.feature(state: VoidFeature.State())
        let void2: Feature<VoidFeature> = FeatureContainer.feature(state: VoidFeature.State())
        
        #expect(void1 === void2)
        #expect(FeatureContainer.numberOffeatures == 1)
    }
    
    @Test func identifiableVoidDependency() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let void1: Feature<IdentifiableVoidFeature> = FeatureContainer.feature(
            state: .init(id: "1"))
        let void2: Feature<IdentifiableVoidFeature> = FeatureContainer.feature(
            state: .init(id: "2"))
        
        #expect(void1 !== void2)
        #expect(FeatureContainer.numberOffeatures == 2)
    }
    
    @Test
    func identifiableVoidDependencyReturnsTheSamefeature() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let void1: Feature<IdentifiableVoidFeature> = FeatureContainer.feature(
            state: .init(id: "1"))
        
        let void2: Feature<IdentifiableVoidFeature> = FeatureContainer.feature(
            state: .init(id: "1"))
        
        #expect(void1 === void2)
    }
}
