//
//  WorkerTests.swift
//  Supervision
//
//  Created by John on 12/25/25.
//

@testable import Supervision
import Testing
import Foundation

// MARK: - Test Environment

private struct TestEnvironment: Sendable {
    let value: Int

    init(value: Int = 42) {
        self.value = value
    }
}

private enum TestAction: Equatable, Sendable {
    case loaded(Int)
    case failed(String)
    case completed
    case cancelled
}

private struct TestError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }

    init(_ message: String = "Test error") {
        self.message = message
    }
}

// MARK: - Run Tests for Different Operation Types

@Suite("Worker run() with different operation types")
struct WorkerRunOperationTests {

    @Test("run with .none operation returns nil")
    func runWithNoneReturnsNil() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let work: Work<TestAction, TestEnvironment, String> = .done
        let env = TestEnvironment()

        let result = await worker.run(work, using: env)

        #expect(result == nil)
    }

    @Test("run with .cancellation operation cancels task and returns nil")
    func runWithCancellationReturnsNil() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        // First, start a long-running task with a cancellation ID
        let startedSignal = SendableBox(value: false)
        let longRunningWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            startedSignal.value = true
            try await Task.sleep(for: .seconds(10))
            return .completed
        }.cancellable(id: "task-to-cancel")

        // Start the long-running task in background
        Task {
            _ = await worker.run(longRunningWork, using: env)
        }

        // Wait for the task to start
        while !startedSignal.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Now run cancellation work
        let cancellationWork: Work<TestAction, TestEnvironment, String> = .cancel("task-to-cancel")
        let result = await worker.run(cancellationWork, using: env)

        #expect(result == nil)

        // Verify the task was removed from tracking
        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)
    }

    @Test("run with .fireAndForget executes operation and returns nil immediately")
    func runWithFireAndForgetReturnsNilImmediately() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let executedBox = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .fireAndForget { _ in
            try await Task.sleep(for: .milliseconds(50))
            executedBox.value = true
        }

        let result = await worker.run(work, using: env)

        // Returns nil immediately
        #expect(result == nil)

        // Operation hasn't completed yet (fire and forget)
        #expect(executedBox.value == false)

        // Wait for the operation to complete
        try await Task.sleep(for: .milliseconds(100))
        #expect(executedBox.value == true)
    }

    @Test("run with .task executes and returns resulting action")
    func runWithTaskReturnsAction() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment(value: 100)

        let work: Work<TestAction, TestEnvironment, String> = .run { environment in
            return .loaded(environment.value * 2)
        }

        let result = await worker.run(work, using: env)

        #expect(result == .loaded(200))
    }

    @Test("run with .task uses environment correctly")
    func runWithTaskUsesEnvironment() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment(value: 7)

        let work: Work<TestAction, TestEnvironment, String> = .run { environment in
            return .loaded(environment.value)
        }

        let result = await worker.run(work, using: env)

        #expect(result == .loaded(7))
    }
}

// MARK: - Error Handling Tests

@Suite("Worker error handling")
struct WorkerErrorHandlingTests {

    @Test("task that throws without error handler returns nil")
    func throwingTaskWithoutHandlerReturnsNil() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            throw TestError("Something went wrong")
        }

        let result = await worker.run(work, using: env)

        // Error is logged, but nil is returned
        #expect(result == nil)
    }

    @Test("task that throws with .catch handler returns action from handler")
    func throwingTaskWithCatchReturnsHandlerAction() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            throw TestError("Network failure")
        }.catch { error in
            return .failed(error.localizedDescription)
        }

        let result = await worker.run(work, using: env)

        #expect(result == .failed("Network failure"))
    }

    @Test("successful task with .catch handler returns normal result")
    func successfulTaskWithCatchReturnsNormalResult() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .completed
        }.catch { _ in
            return .failed("should not be called")
        }

        let result = await worker.run(work, using: env)

        #expect(result == .completed)
    }

    @Test("error handler receives the thrown error")
    func errorHandlerReceivesCorrectError() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let capturedMessageBox = SendableBox<String?>(value: nil)

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            throw TestError("Specific error message")
        }.catch { error in
            capturedMessageBox.value = error.localizedDescription
            return .failed(error.localizedDescription)
        }

        _ = await worker.run(work, using: env)

        #expect(capturedMessageBox.value == "Specific error message")
    }

    @Test("fireAndForget that throws logs error but continues")
    func fireAndForgetThrowingLogsError() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let threwBox = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .fireAndForget { _ in
            threwBox.value = true
            throw TestError("Fire and forget error")
        }

        let result = await worker.run(work, using: env)

        #expect(result == nil)

        // Wait for the fire-and-forget task to execute
        try await Task.sleep(for: .milliseconds(50))
        #expect(threwBox.value == true)
    }
}

// MARK: - Cancellation Tests

@Suite("Worker cancellation")
struct WorkerCancellationTests {

    @Test("cancel(taskID:) cancels a specific running task")
    func cancelSpecificTask() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let startedSignal = SendableBox(value: false)
        let cancelledBox = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            startedSignal.value = true
            do {
                try await Task.sleep(for: .seconds(10))
                return .completed
            } catch is CancellationError {
                cancelledBox.value = true
                throw CancellationError()
            }
        }.cancellable(id: "cancellable-task")

        // Start the task
        Task {
            _ = await worker.run(work, using: env)
        }

        // Wait for task to start
        while !startedSignal.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Cancel the specific task
        await worker.cancel(taskID: "cancellable-task")

        // Give time for cancellation to propagate
        try await Task.sleep(for: .milliseconds(50))

        #expect(cancelledBox.value == true)

        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)
    }

    @Test("cancel(taskID:) with non-existent ID does nothing")
    func cancelNonExistentTask() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()

        // This should not crash or throw
        await worker.cancel(taskID: "non-existent-id")

        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)
    }

    @Test("cancelAll() cancels all tracked tasks")
    func cancelAllTasks() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let started1 = SendableBox(value: false)
        let started2 = SendableBox(value: false)
        let cancelled1 = SendableBox(value: false)
        let cancelled2 = SendableBox(value: false)

        let work1: Work<TestAction, TestEnvironment, String> = .run { _ in
            started1.value = true
            do {
                try await Task.sleep(for: .seconds(10))
                return .loaded(1)
            } catch is CancellationError {
                cancelled1.value = true
                throw CancellationError()
            }
        }.cancellable(id: "task-1")

        let work2: Work<TestAction, TestEnvironment, String> = .run { _ in
            started2.value = true
            do {
                try await Task.sleep(for: .seconds(10))
                return .loaded(2)
            } catch is CancellationError {
                cancelled2.value = true
                throw CancellationError()
            }
        }.cancellable(id: "task-2")

        // Start both tasks
        Task {
            _ = await worker.run(work1, using: env)
        }
        Task {
            _ = await worker.run(work2, using: env)
        }

        // Wait for both to start
        while !started1.value || !started2.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Cancel all
        await worker.cancelAll()

        // Give time for cancellation to propagate
        try await Task.sleep(for: .milliseconds(50))

        #expect(cancelled1.value == true)
        #expect(cancelled2.value == true)

        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)
    }

    @Test("cancelled task responds to cancellation")
    func cancelledTaskRespondsToCheckpoints() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let iterationsBox = SendableBox(value: 0)
        let startedSignal = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            startedSignal.value = true
            for i in 0..<100 {
                try Task.checkCancellation()
                iterationsBox.value = i + 1
                try await Task.sleep(for: .milliseconds(10))
            }
            return .completed
        }.cancellable(id: "iterative-task")

        // Start the task
        Task {
            _ = await worker.run(work, using: env)
        }

        // Wait for task to start
        while !startedSignal.value {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Let it run a few iterations
        try await Task.sleep(for: .milliseconds(50))

        // Cancel the task
        await worker.cancel(taskID: "iterative-task")

        // Give time for cancellation
        try await Task.sleep(for: .milliseconds(50))

        // The task should have stopped before completing all 100 iterations
        let iterations = iterationsBox.value
        #expect(iterations < 100)
        #expect(iterations > 0)
    }
}

// MARK: - Duplicate Cancellation ID Handling Tests

@Suite("Worker duplicate cancellation ID handling")
struct WorkerDuplicateCancellationIDTests {

    @Test("work with same cancellation ID is dropped when already running")
    func duplicateCancellationIDDropsNewWork() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let firstStarted = SendableBox(value: false)
        let secondExecuted = SendableBox(value: false)

        let firstWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            firstStarted.value = true
            try await Task.sleep(for: .seconds(2))
            return .loaded(1)
        }.cancellable(id: "shared-id")

        let secondWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            secondExecuted.value = true
            return .loaded(2)
        }.cancellable(id: "shared-id")

        // Start first work in background
        Task {
            _ = await worker.run(firstWork, using: env)
        }

        // Wait for first to start
        while !firstStarted.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Try to run second work with same ID - should be dropped immediately
        let result = await worker.run(secondWork, using: env)

        // Second work should return nil immediately (dropped)
        #expect(result == nil)

        // Second work's body should never have executed
        #expect(secondExecuted.value == false)
    }

    @Test("existing task continues running when duplicate is dropped")
    func existingTaskContinuesWhenDuplicateDropped() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let firstCompleted = SendableBox(value: false)
        let firstStarted = SendableBox(value: false)

        let firstWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            firstStarted.value = true
            try await Task.sleep(for: .milliseconds(100))
            firstCompleted.value = true
            return .loaded(1)
        }.cancellable(id: "shared-id")

        let secondWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .loaded(2)
        }.cancellable(id: "shared-id")

        // Start first work
        let firstTask = Task {
            await worker.run(firstWork, using: env)
        }

        // Wait for first to start
        while !firstStarted.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Try second (should be dropped)
        _ = await worker.run(secondWork, using: env)

        // First task should still complete
        let firstResult = await firstTask.value

        #expect(firstCompleted.value == true)
        #expect(firstResult == .loaded(1))
    }

    @Test("same ID can be reused after task completes")
    func sameIDCanBeReusedAfterCompletion() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let firstWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .loaded(1)
        }.cancellable(id: "reusable-id")

        let secondWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .loaded(2)
        }.cancellable(id: "reusable-id")

        // Run first work to completion
        let firstResult = await worker.run(firstWork, using: env)
        #expect(firstResult == .loaded(1))

        // Now run second work with same ID - should work since first completed
        let secondResult = await worker.run(secondWork, using: env)
        #expect(secondResult == .loaded(2))
    }

    @Test("same ID can be reused after task is cancelled")
    func sameIDCanBeReusedAfterCancellation() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let firstStarted = SendableBox(value: false)

        let firstWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            firstStarted.value = true
            try await Task.sleep(for: .seconds(10))
            return .loaded(1)
        }.cancellable(id: "cancelled-id")

        // Start first work
        Task {
            _ = await worker.run(firstWork, using: env)
        }

        // Wait for first to start
        while !firstStarted.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Cancel the first task
        await worker.cancel(taskID: "cancelled-id")

        // Give time for cleanup
        try await Task.sleep(for: .milliseconds(50))

        // Now run new work with same ID - should succeed
        let secondWork: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .loaded(2)
        }.cancellable(id: "cancelled-id")

        let result = await worker.run(secondWork, using: env)
        #expect(result == .loaded(2))
    }
}

// MARK: - Task Lifecycle Tests

@Suite("Worker task lifecycle")
struct WorkerTaskLifecycleTests {

    @Test("task is tracked while running")
    func taskIsTrackedWhileRunning() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let startedSignal = SendableBox(value: false)
        let continueSignal = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            startedSignal.value = true
            // Wait for signal to continue
            while !continueSignal.value {
                try await Task.sleep(for: .milliseconds(10))
            }
            return .completed
        }.cancellable(id: "tracked-task")

        // Start the task
        Task {
            _ = await worker.run(work, using: env)
        }

        // Wait for task to start
        while !startedSignal.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Task should be tracked
        let taskCount = await worker.tasks.count
        #expect(taskCount == 1)

        let hasTask = await worker.tasks["tracked-task"] != nil
        #expect(hasTask == true)

        // Signal to continue and complete
        continueSignal.value = true
    }

    @Test("task is removed from tracking after completion")
    func taskIsRemovedAfterCompletion() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .completed
        }.cancellable(id: "completing-task")

        // Run to completion
        _ = await worker.run(work, using: env)

        // Task should be removed
        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)

        let hasTask = await worker.tasks["completing-task"] != nil
        #expect(hasTask == false)
    }

    @Test("task is removed from tracking after error")
    func taskIsRemovedAfterError() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            throw TestError("Task error")
        }.cancellable(id: "erroring-task")

        // Run (will throw and return nil)
        _ = await worker.run(work, using: env)

        // Task should be removed
        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)
    }

    @Test("task without cancellation ID is not tracked")
    func taskWithoutCancellationIDNotTracked() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let startedSignal = SendableBox(value: false)
        let continueSignal = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            startedSignal.value = true
            while !continueSignal.value {
                try await Task.sleep(for: .milliseconds(10))
            }
            return .completed
        }
        // Note: No .cancellable(id:) call

        // Start the task
        Task {
            _ = await worker.run(work, using: env)
        }

        // Wait for task to start
        while !startedSignal.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Task should NOT be tracked (no cancellation ID)
        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)

        // Signal to continue and complete
        continueSignal.value = true
    }

    @Test("multiple tasks can be tracked simultaneously")
    func multipleTasksTrackedSimultaneously() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let started1 = SendableBox(value: false)
        let started2 = SendableBox(value: false)
        let started3 = SendableBox(value: false)
        let continueSignal = SendableBox(value: false)

        let work1: Work<TestAction, TestEnvironment, String> = .run { _ in
            started1.value = true
            while !continueSignal.value {
                try await Task.sleep(for: .milliseconds(10))
            }
            return .loaded(1)
        }.cancellable(id: "task-1")

        let work2: Work<TestAction, TestEnvironment, String> = .run { _ in
            started2.value = true
            while !continueSignal.value {
                try await Task.sleep(for: .milliseconds(10))
            }
            return .loaded(2)
        }.cancellable(id: "task-2")

        let work3: Work<TestAction, TestEnvironment, String> = .run { _ in
            started3.value = true
            while !continueSignal.value {
                try await Task.sleep(for: .milliseconds(10))
            }
            return .loaded(3)
        }.cancellable(id: "task-3")

        // Start all tasks
        Task { _ = await worker.run(work1, using: env) }
        Task { _ = await worker.run(work2, using: env) }
        Task { _ = await worker.run(work3, using: env) }

        // Wait for all to start
        while !started1.value || !started2.value || !started3.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // All three should be tracked
        let taskCount = await worker.tasks.count
        #expect(taskCount == 3)

        // Signal to continue and complete
        continueSignal.value = true
    }
}

// MARK: - Task Priority Tests

@Suite("Worker task priority")
struct WorkerTaskPriorityTests {

    @Test("task respects specified priority")
    func taskRespectsSpecifiedPriority() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let capturedPriorityBox = SendableBox<TaskPriority?>(value: nil)

        let work: Work<TestAction, TestEnvironment, String> = .run(priority: .high) { _ in
            capturedPriorityBox.value = Task.currentPriority
            return .completed
        }

        _ = await worker.run(work, using: env)

        #expect(capturedPriorityBox.value == .high)
    }

    @Test("fireAndForget respects specified priority")
    func fireAndForgetRespectsSpecifiedPriority() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let capturedPriorityBox = SendableBox<TaskPriority?>(value: nil)
        let completedBox = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .fireAndForget(priority: .low) { _ in
            capturedPriorityBox.value = Task.currentPriority
            completedBox.value = true
        }

        _ = await worker.run(work, using: env)

        // Wait for fire-and-forget to complete
        while !completedBox.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(capturedPriorityBox.value == .low)
    }
}

// MARK: - Edge Cases Tests

@Suite("Worker edge cases")
struct WorkerEdgeCaseTests {

    @Test("empty cancellation ID works correctly")
    func emptyCancellationIDWorks() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .completed
        }.cancellable(id: "")

        let result = await worker.run(work, using: env)

        #expect(result == .completed)
    }

    @Test("cancelling with empty ID works")
    func cancellingWithEmptyIDWorks() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let startedSignal = SendableBox(value: false)

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            startedSignal.value = true
            try await Task.sleep(for: .seconds(10))
            return .completed
        }.cancellable(id: "")

        Task {
            _ = await worker.run(work, using: env)
        }

        while !startedSignal.value {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Cancel using empty string ID
        await worker.cancel(taskID: "")

        try await Task.sleep(for: .milliseconds(50))

        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)
    }

    @Test("running many concurrent tasks works correctly")
    func manyConcurrentTasksWork() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()
        let completedCount = SendableBox(value: 0)

        let taskCount = 50
        var tasks: [Task<TestAction?, Never>] = []

        for i in 0..<taskCount {
            let work: Work<TestAction, TestEnvironment, String> = .run { _ in
                completedCount.value += 1
                return .loaded(i)
            }.cancellable(id: "task-\(i)")

            let task = Task {
                await worker.run(work, using: env)
            }
            tasks.append(task)
        }

        // Wait for all tasks to complete
        for task in tasks {
            _ = await task.value
        }

        #expect(completedCount.value == taskCount)

        let trackedCount = await worker.tasks.count
        #expect(trackedCount == 0)
    }

    @Test("task completing with error still cleans up properly")
    func errorCleanupWorks() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            throw TestError("Cleanup test error")
        }.cancellable(id: "error-cleanup-task")

        _ = await worker.run(work, using: env)

        let taskCount = await worker.tasks.count
        #expect(taskCount == 0)

        // Should be able to reuse the ID
        let work2: Work<TestAction, TestEnvironment, String> = .run { _ in
            return .completed
        }.cancellable(id: "error-cleanup-task")

        let result = await worker.run(work2, using: env)
        #expect(result == .completed)
    }

    @Test("CancellationError in task returns nil")
    func cancellationErrorReturnsNil() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            throw CancellationError()
        }

        let result = await worker.run(work, using: env)

        #expect(result == nil)
    }

    @Test("CancellationError with catch handler calls handler")
    func cancellationErrorWithCatchCallsHandler() async throws {
        let worker = Worker<TestAction, TestEnvironment, String>()
        let env = TestEnvironment()

        let work: Work<TestAction, TestEnvironment, String> = .run { _ in
            throw CancellationError()
        }.catch { _ in
            return .cancelled
        }

        let result = await worker.run(work, using: env)

        #expect(result == .cancelled)
    }
}

// MARK: - Helper Types

/// A thread-safe box for capturing values in sendable closures during tests
private final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }

    init(value: T) {
        self._value = value
    }
}
