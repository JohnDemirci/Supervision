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

struct UserFeature: FeatureProtocol {
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

struct DeviceFeature: FeatureProtocol {
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

struct VoidFeature: FeatureProtocol {
    typealias Dependency = Void

    struct State: Equatable {}

    enum Action {
        case nothing
    }

    func process(action: Action, context: borrowing Context<State>) -> FeatureWork {
        return .done
    }
}

struct IdentifiableVoidFeature: FeatureProtocol {
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
    @Test func identicalSupervisors() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let userSupervisor: Feature<UserFeature> = FeatureContainer.supervisor(
            state: UserFeature.State()) {
                UserFeature.Dependency(client: $0.userClient)
            }
        
        let anotherSupervisor: Feature<UserFeature> = FeatureContainer.supervisor(
            state: UserFeature.State()) {
                UserFeature.Dependency(client: $0.userClient)
            }
        
        #expect(userSupervisor === anotherSupervisor)

        #expect(FeatureContainer.numberOfSupervisors == 1)
    }
    
    @Test
    func identicalIndetifiableSupervisorsReturnsTheSameSupervisor() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let deviceState1 = DeviceFeature.State(id: "1")
        let deviceSupervisor: Feature<DeviceFeature> = FeatureContainer.supervisor(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        let deviceSupervisor2: Feature<DeviceFeature> = FeatureContainer.supervisor(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        #expect(deviceSupervisor === deviceSupervisor2)
    }
    
    @Test func multipleSupervisorsWithDifferentIdentities() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let deviceState1 = DeviceFeature.State(id: "1")
        let deviceSupervisor: Feature<DeviceFeature> = FeatureContainer.supervisor(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        let deviceState2 = DeviceFeature.State(id: "2")
        let deviceSupervisor2: Feature<DeviceFeature> = FeatureContainer.supervisor(
            state: deviceState2) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        // Verify that different identities create different supervisors
        #expect(deviceSupervisor !== deviceSupervisor2)
        #expect(FeatureContainer.numberOfSupervisors == 2)
    }
    
    @Test func voidDependency() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let void1: Feature<VoidFeature> = FeatureContainer.supervisor(state: VoidFeature.State())
        let void2: Feature<VoidFeature> = FeatureContainer.supervisor(state: VoidFeature.State())
        
        #expect(void1 === void2)
        #expect(FeatureContainer.numberOfSupervisors == 1)
    }
    
    @Test func identifiableVoidDependency() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let void1: Feature<IdentifiableVoidFeature> = FeatureContainer.supervisor(
            state: .init(id: "1"))
        let void2: Feature<IdentifiableVoidFeature> = FeatureContainer.supervisor(
            state: .init(id: "2"))
        
        #expect(void1 !== void2)
        #expect(FeatureContainer.numberOfSupervisors == 2)
    }
    
    @Test
    func identifiableVoidDependencyReturnsTheSameSupervisor() async throws {
        let FeatureContainer = FeatureContainer(dependency: AppDependency())
        
        let void1: Feature<IdentifiableVoidFeature> = FeatureContainer.supervisor(
            state: .init(id: "1"))
        
        let void2: Feature<IdentifiableVoidFeature> = FeatureContainer.supervisor(
            state: .init(id: "1"))
        
        #expect(void1 === void2)
    }
}
