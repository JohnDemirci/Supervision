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
            dependency: FootballClient()
        )
        
        supervisor.send(.fetchPlayers)
        supervisor.send(.playGame)
        
        try await Task.sleep(for: .seconds(1.5))
        
        #expect(["john"] == supervisor.playerNames)
    }
}

struct FootballClubFeature: FeatureProtocol {
    struct State {
        var playerNames: [String] = []
        var matchesPlayed: Int = 0
        var localLeague: String = ""
    }
    
    typealias Dependency = FootballClient
    
    enum Action {
        case playGame
        case playGameResult(Result<Void, Error>)
        case fetchPlayers
        case fetchPlayersResult(Result<[String], Error>)
    }
    
    func process(action: Action, context: borrowing Context<State>) -> Work<Action, Dependency>  {
        switch action {
        case .playGame:
            return .fireAndForget {
                try await $0.playGame()
            }
        case .playGameResult(let result):
            switch result {
            case .success:
                context.modify(\.matchesPlayed) {
                    $0 += 1
                }
            case .failure:
                break
            }
            return .empty()
        case .fetchPlayers:
            return .run { env in
                try await env.fetchPlayers(delay: .seconds(1), result: .success(["john"]))
            } toAction: { result in
                Action.fetchPlayersResult(result)
            }

        case .fetchPlayersResult(let result):
            switch result {
            case .success(let values):
                context.modify(\.playerNames, to: values)
                return .empty()
            case .failure:
                return .empty()
            }
        }
    }
}

final class FootballClient: Sendable {
    enum Failure: Error { case failure }
    func playGame() async throws -> Void {
        return ()
    }
    func fetchPlayers(
        delay: Duration? = nil,
        result: Result<[String], Error>
    ) async throws -> [String] {
        if let delay {
            try await Task.sleep(for: delay)
        }
        
        switch result {
        case .success(let players):
            return players
        case .failure(let error):
            throw error
        }
    }
}
