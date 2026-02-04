//
//  BroadcastingTests.swift
//  Supervision
//
//  Created by John on 2/4/26.
//

@testable import Supervision
import Foundation
import Testing

@Suite("Broadcasting")
struct BroadcastingTests {
    private struct TestMessage: BroadcastMessage, Sendable {
        let date: Date
        let title: String
        let sender: ReferenceIdentifier
    }

    @Test("messages should be delivered to all subscribers")
    func broadcastToMultipleSubscribers() async throws {
        let hub = FeatureHub()
        let sender = ReferenceIdentifier(id: "sender")
        let message = TestMessage(date: Date(), title: "Hello", sender: sender)

        let stream1 = await hub.subscribe()
        let stream2 = await hub.subscribe()

        let receive1 = Task { () -> FeatureHub.Message? in
            var iterator = stream1.makeAsyncIterator()
            return await iterator.next()
        }
        let receive2 = Task { () -> FeatureHub.Message? in
            var iterator = stream2.makeAsyncIterator()
            return await iterator.next()
        }

        await hub.send(message)

        let received1 = await receive1.value
        let received2 = await receive2.value

        #expect(received1?.title == "Hello")
        #expect(received2?.title == "Hello")
        #expect(received1?.sender == sender)
        #expect(received2?.sender == sender)
    }
}
