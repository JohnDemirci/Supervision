//
//  Broadcasting.swift
//  Supervision
//
//  Created by John Demirci on 2/3/26.
//

import Foundation

public actor FeatureHub {
    public typealias Message = any BroadcastMessage

    private var continuations: [UUID: AsyncStream<Message>.Continuation]

    public init() {
        continuations = [:]
    }

    public func subscribe(
        bufferingPolicy: AsyncStream<Message>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Message> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Message.self,
            bufferingPolicy: bufferingPolicy
        )
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// Broadcasts a message to all current subscribers.
    public func send(_ message: some BroadcastMessage) {
        guard !continuations.isEmpty else { return }

        var terminated: [UUID] = []
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

    /// Finishes all active streams and clears subscribers.
    public func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func removeSubscriber(_ id: UUID) {
        continuations[id] = nil
    }
}

public protocol BroadcastMessage: Sendable {
    var date: Date { get }
    var title: String { get }
    var sender: ReferenceIdentifier { get }
}
