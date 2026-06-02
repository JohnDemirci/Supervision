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
        enum Kind: BroadcastMessageKind {
            case created
            case updated
            case deleted
        }

        let kind: Kind
        let date: Date
        let title: String
        let sender: ReferenceIdentifier?
    }

    struct OtherEvent: BroadcastMessage {
        enum Kind: BroadcastMessageKind {
            case archived
        }

        let kind: Kind
        let date: Date
        let title: String
        let sender: ReferenceIdentifier?
    }

    @Test
    func repeatedSubscriptionAddsMessageKindsToExistingStream() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")

        let firstStream = await broadcaster.subscribe(to: Event.Kind.created, id: featureID)
        let _ = await broadcaster.subscribe(to: Event.Kind.updated, id: featureID)

        await broadcaster.broadcast(
            message: Event(
                kind: .updated,
                date: .now,
                title: "updated",
                sender: featureID
            )
        )

        let received = await nextMessage(from: firstStream)

        #expect((received as? Event)?.title == "updated")
        await broadcaster.finish()
    }

    @Test
    func subscriberIgnoresUnregisteredMessageKinds() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")
        let stream = await broadcaster.subscribe(to: Event.Kind.updated, id: featureID)

        await broadcaster.broadcast(
            message: Event(
                kind: .created,
                date: .now,
                title: "created",
                sender: nil
            )
        )
        await broadcaster.broadcast(
            message: Event(
                kind: .updated,
                date: .now,
                title: "updated",
                sender: nil
            )
        )

        let received = await nextMessage(from: stream)

        #expect((received as? Event)?.title == "updated")
        await broadcaster.finish()
    }

    @Test
    func subscriberReceivesMultipleRegisteredMessageKinds() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")
        let stream = await broadcaster.subscribe(
            to: [Event.Kind.created, .deleted],
            id: featureID
        )

        await broadcaster.broadcast(
            message: Event(
                kind: .created,
                date: .now,
                title: "created",
                sender: nil
            )
        )
        await broadcaster.broadcast(
            message: Event(
                kind: .updated,
                date: .now,
                title: "updated",
                sender: nil
            )
        )
        await broadcaster.broadcast(
            message: Event(
                kind: .deleted,
                date: .now,
                title: "deleted",
                sender: nil
            )
        )

        let received = await nextMessages(count: 2, from: stream)

        #expect(received.compactMap { ($0 as? Event)?.title } == ["created", "deleted"])
        await broadcaster.finish()
    }

    @Test
    func subscriberReceivesMessageKindsOwnedByDifferentFeatures() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")
        let stream = await broadcaster.subscribe(
            to: Event.Kind.created,
            OtherEvent.Kind.archived,
            id: featureID
        )

        await broadcaster.broadcast(
            message: Event(
                kind: .created,
                date: .now,
                title: "created",
                sender: nil
            )
        )
        await broadcaster.broadcast(
            message: OtherEvent(
                kind: .archived,
                date: .now,
                title: "archived",
                sender: nil
            )
        )

        let received = await nextMessages(count: 2, from: stream)

        #expect(received.map(\.title) == ["created", "archived"])
        await broadcaster.finish()
    }

    @Test
    func repeatedSubscriptionsReturnIndependentStreams() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")
        let firstStream = await broadcaster.subscribe(to: Event.Kind.created, id: featureID)
        let secondStream = await broadcaster.subscribe(to: Event.Kind.updated, id: featureID)

        await broadcaster.broadcast(
            message: Event(
                kind: .updated,
                date: .now,
                title: "updated",
                sender: nil
            )
        )

        let firstReceived = await nextMessage(from: firstStream)
        let secondReceived = await nextMessage(from: secondStream)

        #expect((firstReceived as? Event)?.title == "updated")
        #expect((secondReceived as? Event)?.title == "updated")
        await broadcaster.finish()
    }

    @Test
    func abandonedStreamRemovesItsContinuation() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")
        var stream: AsyncStream<any BroadcastMessage>? = await broadcaster.subscribe(
            to: Event.Kind.created,
            id: featureID
        )

        #expect(stream != nil)
        let initialContinuationCount = await broadcaster.continuationCount
        #expect(initialContinuationCount == 1)

        stream = nil
        await Task.megaYield()

        let finalContinuationCount = await broadcaster.continuationCount
        #expect(finalContinuationCount == 0)
    }

    @Test
    func abandoningOneStreamLeavesOtherSameIDStreamActive() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")
        var firstStream: AsyncStream<any BroadcastMessage>? = await broadcaster.subscribe(
            to: Event.Kind.created,
            id: featureID
        )
        let secondStream = await broadcaster.subscribe(to: Event.Kind.updated, id: featureID)

        #expect(firstStream != nil)
        let initialContinuationCount = await broadcaster.continuationCount
        #expect(initialContinuationCount == 2)

        firstStream = nil
        await Task.megaYield()

        let remainingContinuationCount = await broadcaster.continuationCount
        #expect(remainingContinuationCount == 1)

        await broadcaster.broadcast(
            message: Event(
                kind: .updated,
                date: .now,
                title: "updated",
                sender: nil
            )
        )

        let received = await nextMessage(from: secondStream)
        #expect((received as? Event)?.title == "updated")
        await broadcaster.finish()
    }

    @Test
    func finishTerminatesEveryStream() async {
        let broadcaster = Broadcaster()
        let featureID = ReferenceIdentifier(id: "feature")
        let firstStream = await broadcaster.subscribe(to: Event.Kind.created, id: featureID)
        let secondStream = await broadcaster.subscribe(to: Event.Kind.updated, id: featureID)

        let initialContinuationCount = await broadcaster.continuationCount
        #expect(initialContinuationCount == 2)

        await broadcaster.finish()

        let finalContinuationCount = await broadcaster.continuationCount
        #expect(finalContinuationCount == 0)
        #expect(await nextMessage(from: firstStream) == nil)
        #expect(await nextMessage(from: secondStream) == nil)
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
                await Task.megaYield()
                return nil
            }

            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func nextMessages(
        count: Int,
        from stream: AsyncStream<any BroadcastMessage>
    ) async -> [any BroadcastMessage] {
        await withTaskGroup(of: [any BroadcastMessage].self) { group in
            group.addTask {
                var messages: [any BroadcastMessage] = []
                var iterator = stream.makeAsyncIterator()

                while messages.count < count, let message = await iterator.next() {
                    messages.append(message)
                }

                return messages
            }
            group.addTask {
                await Task.megaYield()
                return []
            }

            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }
}
