//
//  Broadcasting.swift
//  Supervision
//
//  Created by John Demirci on 2/3/26.
//

import Foundation

public actor Broadcaster {
    public typealias Message = any BroadcastMessage

    private struct Subscription {
        let token: UUID
        let stream: AsyncStream<Message>
        let continuation: AsyncStream<Message>.Continuation
    }

    private var subscriptions: [ReferenceIdentifier: Subscription]

    public init() {
        subscriptions = [:]
    }

    public func subscribe(
        bufferingPolicy: AsyncStream<Message>.Continuation.BufferingPolicy = .unbounded,
        id: ReferenceIdentifier
    ) -> AsyncStream<Message> {
        if let existing = subscriptions[id] {
            return existing.stream
        }

        let (stream, continuation) = AsyncStream.makeStream(
            of: Message.self,
            bufferingPolicy: bufferingPolicy
        )

        let subscription = Subscription(
            token: UUID(),
            stream: stream,
            continuation: continuation
        )

        subscriptions[id] = subscription

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id, token: subscription.token) }
        }

        return stream
    }

    public func broadcast(message: some BroadcastMessage) {
        guard !subscriptions.isEmpty else { return }

        var terminated: [(ReferenceIdentifier, UUID)] = []
        for (id, subscription) in subscriptions {
            if case .terminated = subscription.continuation.yield(message) {
                terminated.append((id, subscription.token))
            }
        }

        if !terminated.isEmpty {
            for (id, token) in terminated {
                removeSubscriber(id, token: token)
            }
        }
    }

    public func finish() {
        for subscription in subscriptions.values {
            subscription.continuation.finish()
        }
        subscriptions.removeAll()
    }

    private func removeSubscriber(_ id: ReferenceIdentifier, token: UUID) {
        guard subscriptions[id]?.token == token else { return }
        subscriptions[id] = nil
    }
}

public protocol BroadcastMessage: Sendable {
    var date: Date { get }
    var title: String { get }
    var sender: ReferenceIdentifier? { get }
}
