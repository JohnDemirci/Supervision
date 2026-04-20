//
//  BroadcasterTests.swift
//  Supervision
//
//  Created by Codex on 4/20/26.
//

import Foundation
import Testing
@testable import Supervision

@Suite("Broadcaster")
struct BroadcasterTests {
    struct Event: BroadcastMessage {
        let date: Date
        let title: String
        let sender: ReferenceIdentifier?
    }

    @Test
    func duplicateSubscriptionDoesNotReplaceExistingStream() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")

        let firstStream = await broadcaster.subscribe(id: featureID)
        let _ = await broadcaster.subscribe(id: featureID)

        await broadcaster.broadcast(
            message: Event(
                date: .now,
                title: "updated",
                sender: featureID
            )
        )

        let received = await nextMessage(from: firstStream)

        #expect((received as? Event)?.title == "updated")
        await broadcaster.finish()
    }

    private func nextMessage(
        from stream: AsyncStream<any BroadcastMessage>
    ) async -> (any BroadcastMessage)? {
        await withTaskGroup(of: (any BroadcastMessage)?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(250))
                return nil
            }

            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }
}
