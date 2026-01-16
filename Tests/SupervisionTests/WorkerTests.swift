//
//  WorkerTests.swift
//  Supervision
//
//  Created by John on 1/16/26.
//

import Foundation
import Testing
@testable import Supervision

@Suite("Worker")
struct WorkerTests {
    actor Recorder {
        private var values: [Int] = []

        func append(_ value: Int) {
            values.append(value)
        }

        func contains(_ value: Int) -> Bool {
            values.contains(value)
        }
    }

    private func makeFireAndForgetWork(value: Int, id: String) -> Work<Int, Void> {
        Work.run(
            config: Work.RunConfiguration(
                cancellationID: AnyHashableSendable(value: id),
                fireAndForget: true
            ),
            body: { _ in value },
            map: { result in (try? result.get()) ?? -1 }
        )
    }

    @Test
    func fireAndForgetAllowsReuseAfterCompletion() async {
        let worker = Worker<Int, Void>()
        let recorder = Recorder()
        let id = "fire-and-forget"

        await worker.handle(
            work: makeFireAndForgetWork(value: 1, id: id),
            environment: (),
            send: { await recorder.append($0) }
        )

        let firstReceived = await waitUntil(timeout: .seconds(1)) {
            await recorder.contains(1)
        }
        #expect(firstReceived)

        let secondReceived = await retryUntil(timeout: .seconds(1)) {
            await worker.handle(
                work: makeFireAndForgetWork(value: 2, id: id),
                environment: (),
                send: { await recorder.append($0) }
            )
            return await recorder.contains(2)
        }
        #expect(secondReceived)
    }

    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10),
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return await condition()
    }

    private func retryUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10),
        _ action: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await action() { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return await action()
    }
}
