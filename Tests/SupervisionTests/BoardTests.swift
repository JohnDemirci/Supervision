//
//  BoardTests.swift
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
    func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
        switch action {
        case .changeName(let newName):
            context.modify(\.name, to: newName)
            return .empty()
        }
    }
    
    struct Dependency: Sendable {
        let client: UserClient
    }
    
    struct State {
        var name: String = "something"
    }
    
    enum Action {
        case changeName(String)
    }
}

struct DeviceFeature: FeatureProtocol {
    func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency> {
        return .empty()
    }
    
    struct Dependency: Sendable {
        let client: UserClient
    }
    
    struct State: Identifiable {
        let id: String
        var devices: [String] = []
    }
    
    enum Action {
        case nothing
    }
}

struct VoidFeature: FeatureProtocol {
    typealias Dependency = Void
    
    struct State {}
    
    enum Action {
        case nothing
    }
    
    func process(action: Action, context: borrowing Context<State>) -> Work<Action, Void> {
        return .empty()
    }
}

struct IdentifiableVoidFeature: FeatureProtocol {
    typealias Dependency = Void
    
    struct State: Identifiable {
        let id: String
    }
    
    enum Action {
        case nothing
    }
    
    func process(action: Action, context: borrowing Context<State>) -> Work<Action, Void> {
        return .empty()
    }
}

@MainActor
@Suite("Board")
struct BoardTests {
    @Test func identicalSupervisors() async throws {
        let board = Board(dependency: AppDependency())
        
        let userSupervisor: Supervisor<UserFeature> = board.supervisor(
            state: UserFeature.State()) {
                UserFeature.Dependency(client: $0.userClient)
            }
        
        let anotherSupervisor: Supervisor<UserFeature> = board.supervisor(
            state: UserFeature.State()) {
                UserFeature.Dependency(client: $0.userClient)
            }
        
        #expect(userSupervisor === anotherSupervisor)
        
        try await Task.sleep(for: .seconds(3))
        
        #expect(board.numberOfSupervisors == 1)
    }
    
    @Test
    func identicalIndetifiableSupervisorsReturnsTheSameSupervisor() async throws {
        let board = Board(dependency: AppDependency())
        
        let deviceState1 = DeviceFeature.State(id: "1")
        let deviceSupervisor: Supervisor<DeviceFeature> = board.supervisor(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        let deviceSupervisor2: Supervisor<DeviceFeature> = board.supervisor(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        #expect(deviceSupervisor === deviceSupervisor2)
    }
    
    @Test func multipleSupervisorsWithDifferentIdentities() async throws {
        let board = Board(dependency: AppDependency())
        
        let deviceState1 = DeviceFeature.State(id: "1")
        let deviceSupervisor: Supervisor<DeviceFeature> = board.supervisor(
            state: deviceState1) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        let deviceState2 = DeviceFeature.State(id: "2")
        let deviceSupervisor2: Supervisor<DeviceFeature> = board.supervisor(
            state: deviceState2) {
                DeviceFeature.Dependency(client: $0.userClient)
            }
        
        // Verify that different identities create different supervisors
        #expect(deviceSupervisor !== deviceSupervisor2)
        #expect(board.numberOfSupervisors == 2)
    }
    
    @Test func voidDependency() async throws {
        let board = Board(dependency: AppDependency())
        
        let void1: Supervisor<VoidFeature> = board.supervisor(state: VoidFeature.State())
        let void2: Supervisor<VoidFeature> = board.supervisor(state: VoidFeature.State())
        
        #expect(void1 === void2)
        #expect(board.numberOfSupervisors == 1)
    }
    
    @Test func identifiableVoidDependency() async throws {
        let board = Board(dependency: AppDependency())
        
        let void1: Supervisor<IdentifiableVoidFeature> = board.supervisor(
            state: .init(id: "1"))
        let void2: Supervisor<IdentifiableVoidFeature> = board.supervisor(
            state: .init(id: "2"))
        
        #expect(void1 !== void2)
        #expect(board.numberOfSupervisors == 2)
    }
    
    @Test
    func identifiableVoidDependencyReturnsTheSameSupervisor() async throws {
        let board = Board(dependency: AppDependency())
        
        let void1: Supervisor<IdentifiableVoidFeature> = board.supervisor(
            state: .init(id: "1"))
        
        let void2: Supervisor<IdentifiableVoidFeature> = board.supervisor(
            state: .init(id: "1"))
        
        #expect(void1 === void2)
    }
}
