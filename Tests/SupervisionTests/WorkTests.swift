//
//  WorkTests.swift
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
    case transformed(String)
}

// MARK: - Factory Method Tests

@MainActor
@Suite("Work Factory Methods")
struct WorkFactoryTests {

    @Test("empty() creates a none operation")
    func emptyCreatesNoneOperation() async throws {
        let work: Work<TestAction, TestEnvironment> = .empty()

        switch work.operation {
        case .none:
            // Success - this is the expected case
            break
        case .cancellation, .fireAndForget, .task:
            Issue.record("Expected .none operation but got different type")
        }

        #expect(work.cancellationID == nil)
        #expect(work.onError == nil)
    }

    @Test("cancel(_:) creates a cancellation operation with correct ID")
    func cancelCreatesCorrectOperation() async throws {
        let cancellationID = "test-cancellation-id"
        let work: Work<TestAction, TestEnvironment> = .cancel(cancellationID)

        switch work.operation {
        case .cancellation(let id):
            #expect(id == cancellationID)
        case .none, .fireAndForget, .task:
            Issue.record("Expected .cancellation operation but got different type")
        }

        // The work's cancellationID property should be nil (it's not a cancellable work, it IS a cancellation)
        #expect(work.cancellationID == nil)
        #expect(work.onError == nil)
    }

    @Test("cancel(_:) with empty string ID")
    func cancelWithEmptyID() async throws {
        let work: Work<TestAction, TestEnvironment> = .cancel("")

        switch work.operation {
        case .cancellation(let id):
            #expect(id == "")
        case .none, .fireAndForget, .task:
            Issue.record("Expected .cancellation operation")
        }
    }

    @Test("fireAndForget creates correct operation type")
    func fireAndForgetCreatesCorrectOperation() async throws {
        let executedBox = SendableBox(value: false)
        let work: Work<TestAction, TestEnvironment> = .fireAndForget { _ in
            executedBox.value = true
        }

        switch work.operation {
        case .fireAndForget(let priority, let body):
            #expect(priority == nil)
            // Execute the body to verify it works
            try await body(TestEnvironment())
            #expect(executedBox.value == true)
        case .none, .cancellation, .task:
            Issue.record("Expected .fireAndForget operation but got different type")
        }

        #expect(work.cancellationID == nil)
        #expect(work.onError == nil)
    }

    @Test("fireAndForget with custom priority")
    func fireAndForgetWithPriority() async throws {
        let work: Work<TestAction, TestEnvironment> = .fireAndForget(priority: .high) { _ in }

        switch work.operation {
        case .fireAndForget(let priority, _):
            #expect(priority == .high)
        case .none, .cancellation, .task:
            Issue.record("Expected .fireAndForget operation")
        }
    }

    @Test("fireAndForget can access environment")
    func fireAndForgetAccessesEnvironment() async throws {
        let capturedValueBox = SendableBox<Int?>(value: nil)
        let work: Work<TestAction, TestEnvironment> = .fireAndForget { env in
            capturedValueBox.value = env.value
        }

        switch work.operation {
        case .fireAndForget(_, let body):
            try await body(TestEnvironment(value: 100))
            #expect(capturedValueBox.value == 100)
        default:
            Issue.record("Expected .fireAndForget operation")
        }
    }

    @Test("run creates correct operation type")
    func runCreatesCorrectOperation() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { env in
            return .loaded(env.value)
        }

        switch work.operation {
        case .task(let priority, let body):
            #expect(priority == nil)
            let result = try await body(TestEnvironment(value: 99))
            #expect(result == .loaded(99))
        case .none, .cancellation, .fireAndForget:
            Issue.record("Expected .task operation but got different type")
        }

        #expect(work.cancellationID == nil)
        #expect(work.onError == nil)
    }

    @Test("run with custom priority")
    func runWithPriority() async throws {
        let work: Work<TestAction, TestEnvironment> = .run(priority: .low) { _ in
            return .completed
        }

        switch work.operation {
        case .task(let priority, _):
            #expect(priority == .low)
        case .none, .cancellation, .fireAndForget:
            Issue.record("Expected .task operation")
        }
    }

    @Test("run(_:toAction:) handles success result")
    func runToActionHandlesSuccess() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { env in
            return env.value * 2
        } toAction: { result in
            switch result {
            case .success(let value):
                return .loaded(value)
            case .failure:
                return .failed("error")
            }
        }

        switch work.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment(value: 21))
            #expect(result == .loaded(42))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("run(_:toAction:) handles failure result")
    func runToActionHandlesFailure() async throws {
        struct TestError: Error, CustomStringConvertible {
            let message: String
            var description: String { message }
        }

        let work: Work<TestAction, TestEnvironment> = .run { (_: TestEnvironment) -> Int in
            throw TestError(message: "Something went wrong")
        } toAction: { result in
            switch result {
            case .success(let value):
                return .loaded(value)
            case .failure(let error):
                return .failed(String(describing: error))
            }
        }

        switch work.operation {
        case .task(_, let body):
            // The toAction closure catches the error and converts it
            let result = try await body(TestEnvironment())
            #expect(result == .failed("Something went wrong"))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("run(_:toAction:) with custom priority")
    func runToActionWithPriority() async throws {
        let work: Work<TestAction, TestEnvironment> = .run(priority: .userInitiated) { _ in
            return 10
        } toAction: { result in
            switch result {
            case .success(let value):
                return .loaded(value)
            case .failure:
                return .failed("error")
            }
        }

        switch work.operation {
        case .task(let priority, _):
            #expect(priority == .userInitiated)
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("run(_:toAction:) passes Result directly")
    func runToActionPassesResultDirectly() async throws {
        enum Action: Equatable {
            case response(Result<Int, TestFailure>)
        }

        enum TestFailure: Error, Equatable {
            case networkError
        }

        // Success case
        let successWork: Work<Action, TestEnvironment> = .run { _ in
            return 42
        } toAction: { result in
            switch result {
            case .success(let value):
                return .response(.success(value))
            case .failure:
                return .response(.failure(.networkError))
            }
        }

        switch successWork.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment())
            #expect(result == .response(.success(42)))
        default:
            Issue.record("Expected .task operation")
        }
    }
}

// MARK: - Transformation Tests

@MainActor
@Suite("Work Transformations")
struct WorkTransformationTests {

    @Test("map transforms output correctly")
    func mapTransformsOutput() async throws {
        let work: Work<Int, TestEnvironment> = .run { env in
            return env.value
        }

        let mappedWork = try work.map { value in
            TestAction.loaded(value * 2)
        }

        switch mappedWork.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment(value: 10))
            #expect(result == .loaded(20))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("map preserves cancellation ID")
    func mapPreservesCancellationID() async throws {
        let work: Work<Int, TestEnvironment> = .run { _ in
            return 42
        }.cancellable(id: "test-id")

        let mappedWork = try work.map { value in
            TestAction.loaded(value)
        }

        #expect(mappedWork.cancellationID == "test-id")
    }

    @Test("map throws on none operation")
    func mapThrowsOnNone() async throws {
        let work: Work<TestAction, TestEnvironment> = .empty()

        #expect {
            try work.map { $0 }
        } throws: { error in
            guard let failure = error as? Work<TestAction, TestEnvironment>.Failure else {
                return false
            }
            return failure.description == "Attempting to map a non-task work unit"
        }
    }

    @Test("map throws on cancellation operation")
    func mapThrowsOnCancellation() async throws {
        let work: Work<TestAction, TestEnvironment> = .cancel("some-id")

        #expect {
            try work.map { $0 }
        } throws: { error in
            guard let failure = error as? Work<TestAction, TestEnvironment>.Failure else {
                return false
            }
            return failure.description == "Attempting to map a cancellation work unit"
        }
    }

    @Test("map throws on fireAndForget operation")
    func mapThrowsOnFireAndForget() async throws {
        let work: Work<TestAction, TestEnvironment> = .fireAndForget { _ in }

        #expect {
            try work.map { $0 }
        } throws: { error in
            guard let failure = error as? Work<TestAction, TestEnvironment>.Failure else {
                return false
            }
            return failure.description == "Attempting to map a fire-and-forget work unit"
        }
    }

    @Test("flatMap chains work correctly")
    func flatMapChainsWork() async throws {
        let work: Work<Int, TestEnvironment> = .run { env in
            return env.value
        }

        let flatMappedWork = try work.flatMap { value in
            Work<TestAction, TestEnvironment>.run { _ in
                return .loaded(value * 3)
            }
        }

        switch flatMappedWork.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment(value: 5))
            #expect(result == .loaded(15))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("flatMap preserves priority from original work")
    func flatMapPreservesPriority() async throws {
        let work: Work<Int, TestEnvironment> = .run(priority: .background) { _ in
            return 42
        }

        let flatMappedWork = try work.flatMap { value in
            Work<TestAction, TestEnvironment>.run { _ in
                return .loaded(value)
            }
        }

        switch flatMappedWork.operation {
        case .task(let priority, _):
            #expect(priority == .background)
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("flatMap throws on none operation")
    func flatMapThrowsOnNone() async throws {
        let work: Work<TestAction, TestEnvironment> = .empty()

        let flatMapTransform: @Sendable (TestAction) -> Work<String, TestEnvironment> = { _ in
            Work<String, TestEnvironment>.run { _ in "result" }
        }

        #expect {
            try work.flatMap(flatMapTransform)
        } throws: { error in
            guard let failure = error as? Work<TestAction, TestEnvironment>.Failure else {
                return false
            }
            return failure.description == "Attempting to flatMap a none work unit"
        }
    }

    @Test("flatMap throws on cancellation operation")
    func flatMapThrowsOnCancellation() async throws {
        let work: Work<TestAction, TestEnvironment> = .cancel("some-id")

        let flatMapTransform: @Sendable (TestAction) -> Work<String, TestEnvironment> = { _ in
            Work<String, TestEnvironment>.run { _ in "result" }
        }

        #expect {
            try work.flatMap(flatMapTransform)
        } throws: { error in
            guard let failure = error as? Work<TestAction, TestEnvironment>.Failure else {
                return false
            }
            return failure.description == "Attempting to flatMap a cancellation work unit"
        }
    }

    @Test("flatMap throws on fireAndForget operation")
    func flatMapThrowsOnFireAndForget() async throws {
        let work: Work<TestAction, TestEnvironment> = .fireAndForget { _ in }

        let flatMapTransform: @Sendable (TestAction) -> Work<String, TestEnvironment> = { _ in
            Work<String, TestEnvironment>.run { _ in "result" }
        }

        #expect {
            try work.flatMap(flatMapTransform)
        } throws: { error in
            guard let failure = error as? Work<TestAction, TestEnvironment>.Failure else {
                return false
            }
            return failure.description == "Attempting to flatMap a fireAndForget work unit"
        }
    }

    @Test("catch attaches error handler")
    func catchAttachesErrorHandler() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }.catch { error in
            return .failed(String(describing: error))
        }

        #expect(work.onError != nil)

        // Verify the error handler works correctly
        struct TestError: Error, CustomStringConvertible {
            var description: String { "Test error message" }
        }

        if let onError = work.onError {
            let result = onError(TestError())
            #expect(result == .failed("Test error message"))
        }
    }

    @Test("catch preserves operation")
    func catchPreservesOperation() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }.catch { _ in
            return .failed("error")
        }

        switch work.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment())
            #expect(result == .completed)
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("catch preserves cancellation ID")
    func catchPreservesCancellationID() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }
        .cancellable(id: "my-task")
        .catch { _ in
            return .failed("error")
        }

        #expect(work.cancellationID == "my-task")
    }

    @Test("catch can be chained")
    func catchCanBeChained() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }
        .catch { _ in
            return .failed("first error handler")
        }

        // Applying catch again replaces the previous handler
        let workWithNewCatch = work.catch { _ in
            return .failed("second error handler")
        }

        if let onError = workWithNewCatch.onError {
            struct TestError: Error {}
            let result = onError(TestError())
            #expect(result == .failed("second error handler"))
        }
    }
}

// MARK: - Cancellable Tests

@MainActor
@Suite("Work Cancellable")
struct WorkCancellableTests {

    @Test("cancellable(id:) attaches the ID correctly")
    func cancellableAttachesID() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }.cancellable(id: "my-unique-id")

        #expect(work.cancellationID == "my-unique-id")
    }

    @Test("cancellable preserves operation")
    func cancellablePreservesOperation() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .loaded(42)
        }.cancellable(id: "test-id")

        switch work.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment())
            #expect(result == .loaded(42))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("cancellable preserves error handler")
    func cancellablePreservesErrorHandler() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }
        .catch { _ in
            return .failed("caught error")
        }
        .cancellable(id: "test-id")

        #expect(work.onError != nil)
        #expect(work.cancellationID == "test-id")

        if let onError = work.onError {
            struct TestError: Error {}
            let result = onError(TestError())
            #expect(result == .failed("caught error"))
        }
    }

    @Test("cancellable can be called on empty work")
    func cancellableOnEmpty() async throws {
        let work: Work<TestAction, TestEnvironment> = Work<TestAction, TestEnvironment>.empty()
            .cancellable(id: "empty-id")

        #expect(work.cancellationID == "empty-id")

        switch work.operation {
        case .none:
            break // Expected
        default:
            Issue.record("Expected .none operation")
        }
    }

    @Test("cancellable can be called on fireAndForget work")
    func cancellableOnFireAndForget() async throws {
        let work: Work<TestAction, TestEnvironment> = Work<TestAction, TestEnvironment>.fireAndForget { _ in }
            .cancellable(id: "fire-id")

        #expect(work.cancellationID == "fire-id")

        switch work.operation {
        case .fireAndForget:
            break // Expected
        default:
            Issue.record("Expected .fireAndForget operation")
        }
    }

    @Test("cancellable ID can be overwritten")
    func cancellableIDCanBeOverwritten() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }
        .cancellable(id: "first-id")
        .cancellable(id: "second-id")

        #expect(work.cancellationID == "second-id")
    }

    @Test("cancellable with empty string ID")
    func cancellableWithEmptyID() async throws {
        let work: Work<TestAction, TestEnvironment> = .run { _ in
            return .completed
        }.cancellable(id: "")

        #expect(work.cancellationID == "")
    }
}

// MARK: - Failure Type Tests

@Suite("Work Failure Type")
struct WorkFailureTests {

    @Test("Failure error message is correct")
    func failureErrorMessage() async throws {
        let failure = Work<TestAction, TestEnvironment>.Failure.message("Test error message")

        #expect(failure.description == "Test error message")
    }

    @Test("Failure with empty message")
    func failureWithEmptyMessage() async throws {
        let failure = Work<TestAction, TestEnvironment>.Failure.message("")

        #expect(failure.description == "")
    }

    @Test("Failure conforms to Error")
    func failureConformsToError() async throws {
        let failure: Error = Work<TestAction, TestEnvironment>.Failure.message("error")

        #expect(failure is Work<TestAction, TestEnvironment>.Failure)
    }

    @Test("Failure conforms to CustomStringConvertible")
    func failureConformsToCustomStringConvertible() async throws {
        let failure: CustomStringConvertible = Work<TestAction, TestEnvironment>.Failure.message("custom description")

        #expect(failure.description == "custom description")
    }

    @Test("Different Failure messages are distinguishable")
    func differentFailureMessages() async throws {
        let failure1 = Work<TestAction, TestEnvironment>.Failure.message("First error")
        let failure2 = Work<TestAction, TestEnvironment>.Failure.message("Second error")

        #expect(failure1.description != failure2.description)
        #expect(failure1.description == "First error")
        #expect(failure2.description == "Second error")
    }
}

// MARK: - Integration Tests

@MainActor
@Suite("Work Integration")
struct WorkIntegrationTests {

    @Test("map and cancellable can be combined")
    func mapAndCancellableCombined() async throws {
        let work = try Work<Int, TestEnvironment>.run { env in
            return env.value
        }
        .map { value in
            TestAction.loaded(value * 2)
        }
        .cancellable(id: "combined-id")

        #expect(work.cancellationID == "combined-id")

        switch work.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment(value: 5))
            #expect(result == .loaded(10))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("flatMap and catch can be combined")
    func flatMapAndCatchCombined() async throws {
        let work = try Work<Int, TestEnvironment>.run { _ in
            return 10
        }
        .flatMap { value in
            Work<TestAction, TestEnvironment>.run { _ in
                return .loaded(value + 5)
            }
        }
        .catch { error in
            return .failed(String(describing: error))
        }

        #expect(work.onError != nil)

        switch work.operation {
        case .task(_, let body):
            let result = try await body(TestEnvironment())
            #expect(result == .loaded(15))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("multiple transformations chain correctly")
    func multipleTransformationsChain() async throws {
        let work = try Work<Int, TestEnvironment>.run { env in
            return env.value
        }
        .map { value in
            value * 2
        }
        .map { value in
            value + 10
        }
        .map { value in
            TestAction.loaded(value)
        }
        .cancellable(id: "chain-id")
        .catch { _ in
            return .failed("error")
        }

        #expect(work.cancellationID == "chain-id")
        #expect(work.onError != nil)

        switch work.operation {
        case .task(_, let body):
            // (5 * 2) + 10 = 20
            let result = try await body(TestEnvironment(value: 5))
            #expect(result == .loaded(20))
        default:
            Issue.record("Expected .task operation")
        }
    }

    @Test("work with throwing body")
    func workWithThrowingBody() async throws {
        struct OperationError: Error, CustomStringConvertible {
            var description: String { "Operation failed" }
        }

        let work: Work<TestAction, TestEnvironment> = .run { _ in
            throw OperationError()
        }.catch { _ in
            return .failed("Operation failed")
        }

        // The error handler is attached
        #expect(work.onError != nil)

        // Verify the error handler produces correct output
        if let onError = work.onError {
            let result = onError(OperationError())
            #expect(result == .failed("Operation failed"))
        }
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
