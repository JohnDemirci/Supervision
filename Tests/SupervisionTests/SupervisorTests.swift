//
//  SupervisorTests.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

@testable import Supervision
import Testing

@MainActor
@Suite("SupervisorTests")
struct SupervisorTests {
    @Test
    func testSend() async throws {
        let supervisor: Supervisor<FootballClubFeature> = .init(
            state: FootballClubFeature.State(),
            dependency: ()
        )
        
        supervisor.send(.addPlayer("James"))
        supervisor.send(.playMatch)
        supervisor.send(.setLocalLeague("Premier League"))
        
        #expect(supervisor.state.playerNames == ["James"])
        #expect(supervisor.state.matchesPlayed == 1)
        #expect(supervisor.state.localLeague == "Premier League")
    }
}

struct FootballClubFeature: FeatureProtocol {
    struct State {
        var playerNames: [String] = []
        var matchesPlayed: Int = 0
        var localLeague: String = ""
    }
    
    typealias Dependency = Void
    
    enum Action {
        case addPlayer(String)
        case playMatch
        case setLocalLeague(String)
    }
    
    func process(action: Action, context: borrowing Context<State>, dependency: Void) {
        switch action {
        case .addPlayer(let name):
            context.batch {
                $0.playerNames.wrappedValue.append(name)
            }
            
        case .playMatch:
            context.mutate(\.matchesPlayed, to: context.matchesPlayed + 1)
            
        case .setLocalLeague(let name):
            context.mutate(\.localLeague, to: name)
        }
    }
}
