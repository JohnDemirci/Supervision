//
//  Broadcasting.swift
//  Supervision
//
//  Created by John Demirci on 2/3/26.
//

import Foundation

public actor Broadcaster {
    public typealias Message = any BroadcastMessage

    private var continuations: [ReferenceIdentifier: AsyncStream<Message>.Continuation]

    public init() {
        continuations = [:]
    }

    public func subscribe(
        bufferingPolicy: AsyncStream<Message>.Continuation.BufferingPolicy = .unbounded,
        id: ReferenceIdentifier
    ) -> AsyncStream<Message> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Message.self,
            bufferingPolicy: bufferingPolicy
        )
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    public func broadcast(message: some BroadcastMessage) {
        guard !continuations.isEmpty else { return }

        var terminated: [ReferenceIdentifier] = []
        for (id, continuation) in continuations {
            if case .terminated = continuation.yield(message) {
                terminated.append(id)
            }
        }

        if !terminated.isEmpty {
            for id in terminated {
                continuations[id] = nil
            }
        }
    }

    public func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func removeSubscriber(_ id: ReferenceIdentifier) {
        continuations[id] = nil
    }
}

public protocol BroadcastMessage: Sendable {
    var date: Date { get }
    var title: String { get }
    var sender: ReferenceIdentifier? { get }
}
