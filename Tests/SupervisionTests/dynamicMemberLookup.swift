//
//  dynamicMemberLookup.swift
//  Supervision
//
//  Created by John on 11/29/25.
//

import Testing
import Supervision

@MainActor
struct SupervisorDynamicMemberLookupTests {
    @Test
    func accessProperties() {
        let supervisor = Supervisor<FootballClubFeature>.init(
            state: FootballClubFeature.State(),
            dependency: ()
        )
        
        supervisor.send(.playMatch)
        
        #expect(supervisor.matchesPlayed == 1)
    }
}
