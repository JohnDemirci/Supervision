import Testing
@testable import Supervision

@Suite("Worker throttle")
struct WorkerThrottleTests {
    private enum CancelID: Hashable, Sendable {
        case translation
    }

    private actor Recorder {
        private var actions: [String] = []

        func record(_ action: String) {
            actions.append(action)
        }

        func snapshot() -> [String] {
            actions
        }
    }

    private func makeWork(
        label: String,
        bodyDelay: Duration? = nil,
        debounce: Duration? = nil
    ) -> Work<String, Void> {
        var work = Work<String, Void>.run(
            body: { _ in
                if let bodyDelay {
                    try await Task.sleep(for: bodyDelay)
                }

                return label
            },
            map: { result in
                switch result {
                case .success(let value):
                    return value
                case .failure:
                    return "failed"
                }
            }
        )
        .cancellable(id: CancelID.translation, cancelInFlight: true)
        .throttle(for: .seconds(1))

        if let debounce {
            work = work.debounce(for: debounce)
        }

        return work
    }

    @Test
    func throttledReplacementDoesNotCancelActiveWork() async {
        let worker = Worker<String, Void>()
        let recorder = Recorder()

        let firstTask = Task {
            await worker.handle(
                work: makeWork(label: "first", bodyDelay: .milliseconds(100)),
                environment: (),
                send: { await recorder.record($0) }
            )
        }

        try? await Task.sleep(for: .milliseconds(20))

        let secondResult = await worker.handle(
            work: makeWork(label: "second"),
            environment: (),
            send: { await recorder.record($0) }
        )
        let firstResult = await firstTask.value

        #expect(secondResult == true)
        #expect(firstResult == true)
        #expect(await recorder.snapshot() == ["first"])
    }

    @Test
    func debounceDoesNotStartThrottleWindowBeforeExecution() async {
        let worker = Worker<String, Void>()
        let recorder = Recorder()

        let firstTask = Task {
            await worker.handle(
                work: makeWork(label: "first", debounce: .milliseconds(150)),
                environment: (),
                send: { await recorder.record($0) }
            )
        }

        try? await Task.sleep(for: .milliseconds(20))

        let secondResult = await worker.handle(
            work: makeWork(label: "second", debounce: .milliseconds(150)),
            environment: (),
            send: { await recorder.record($0) }
        )
        let firstResult = await firstTask.value

        #expect(secondResult == true)
        #expect(firstResult == false)
        #expect(await recorder.snapshot() == ["second"])
    }
}
