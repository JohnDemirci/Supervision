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
        var continuations: [UUID: AsyncStream<Message>.Continuation]
        var messageKinds: Set<AnyHashableSendable>
    }

    private var subscriptions: [ReferenceIdentifier: Subscription]

    public init() {
        subscriptions = [:]
    }

    public func subscribe<MessageKind: BroadcastMessageKind>(
        to messageKinds: Set<MessageKind>,
        bufferingPolicy: AsyncStream<Message>.Continuation.BufferingPolicy = .unbounded,
        id: ReferenceIdentifier
    ) -> AsyncStream<Message> {
        subscribe(
            to: Set(messageKinds.map(AnyHashableSendable.init(value:))),
            bufferingPolicy: bufferingPolicy,
            id: id
        )
    }

    public func subscribe<
        FirstMessageKind: BroadcastMessageKind,
        each AdditionalMessageKind: BroadcastMessageKind
    >(
        to firstMessageKind: FirstMessageKind,
        _ additionalMessageKinds: repeat each AdditionalMessageKind,
        bufferingPolicy: AsyncStream<Message>.Continuation.BufferingPolicy = .unbounded,
        id: ReferenceIdentifier
    ) -> AsyncStream<Message> {
        var messageKinds = Set([AnyHashableSendable(value: firstMessageKind)])
        repeat _ = messageKinds.insert(AnyHashableSendable(value: each additionalMessageKinds))

        return subscribe(
            to: messageKinds,
            bufferingPolicy: bufferingPolicy,
            id: id
        )
    }

    private func subscribe(
        to messageKinds: Set<AnyHashableSendable>,
        bufferingPolicy: AsyncStream<Message>.Continuation.BufferingPolicy,
        id: ReferenceIdentifier
    ) -> AsyncStream<Message> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Message.self,
            bufferingPolicy: bufferingPolicy
        )

        let token = UUID()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id, token: token) }
        }

        if var existing = subscriptions[id] {
            existing.messageKinds.formUnion(messageKinds)
            existing.continuations[token] = continuation
            subscriptions[id] = existing
        } else {
            subscriptions[id] = Subscription(
                continuations: [token: continuation],
                messageKinds: messageKinds
            )
        }

        return stream
    }

    public func broadcast(message: some BroadcastMessage) {
        guard !subscriptions.isEmpty else { return }

        let messageKind = AnyHashableSendable(value: message.kind)
        var terminated: [(ReferenceIdentifier, UUID)] = []
        for (id, subscription) in subscriptions {
            guard subscription.messageKinds.contains(messageKind) else {
                continue
            }

            for (token, continuation) in subscription.continuations {
                if case .terminated = continuation.yield(message) {
                    terminated.append((id, token))
                }
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
            for continuation in subscription.continuations.values {
                continuation.finish()
            }
        }
        subscriptions.removeAll()
    }

    private func removeSubscriber(_ id: ReferenceIdentifier, token: UUID) {
        guard var subscription = subscriptions[id] else { return }
        subscription.continuations[token] = nil

        if subscription.continuations.isEmpty {
            subscriptions[id] = nil
        } else {
            subscriptions[id] = subscription
        }
    }

    var continuationCount: Int {
        subscriptions.values.reduce(0) { count, subscription in
            count + subscription.continuations.count
        }
    }
}

public protocol BroadcastMessageKind: Hashable, Sendable {}

public protocol BroadcastMessage: Sendable {
    associatedtype MessageKind: BroadcastMessageKind

    var kind: MessageKind { get }
    var date: Date { get }
    var title: String { get }
    var sender: ReferenceIdentifier? { get }
}
