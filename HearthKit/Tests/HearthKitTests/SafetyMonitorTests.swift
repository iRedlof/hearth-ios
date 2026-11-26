import Testing
@testable import HearthKit

@Suite("SafetyMonitor")
struct SafetyMonitorTests {

    // Mock ActionExecutor for testing
    actor MockAction: ActionExecutor {
        var executeCallCount = 0
        var verifyCallCount = 0
        var shouldExecuteThrow = false
        var shouldVerifyThrow = false
        var verifyResults: [Bool] = []

        func execute() async throws {
            executeCallCount += 1
            if shouldExecuteThrow {
                throw TestError.executeFailed
            }
        }

        func verify() async throws -> Bool {
            verifyCallCount += 1
            if shouldVerifyThrow {
                throw TestError.verifyFailed
            }
            if verifyResults.isEmpty {
                return false
            }
            return verifyResults.removeFirst()
        }
    }

    // Actor to track alarm calls in a Sendable-safe way
    actor AlarmTracker {
        var called = false
        func markCalled() {
            called = true
        }
    }

    enum TestError: Error {
        case executeFailed
        case verifyFailed
    }

    @Test("verify true on first attempt → execute once, no alarm")
    func successFirstTry() async {
        let action = MockAction()
        await action.setVerifyResults([true])
        let tracker = AlarmTracker()

        await monitorWithRetry(
            action,
            retryDelay: .seconds(0),
            sleep: { _ in },
            onFinalFailure: { await tracker.markCalled() }
        )

        let executeCount = await action.executeCallCount
        let verifyCount = await action.verifyCallCount
        let alarmCalled = await tracker.called

        #expect(executeCount == 1)
        #expect(verifyCount == 1)
        #expect(alarmCalled == false)
    }

    @Test("verify false first, true after retry → execute twice, no alarm")
    func successAfterRetry() async {
        let action = MockAction()
        await action.setVerifyResults([false, true])
        let tracker = AlarmTracker()

        await monitorWithRetry(
            action,
            retryDelay: .seconds(0),
            sleep: { _ in },
            onFinalFailure: { await tracker.markCalled() }
        )

        let executeCount = await action.executeCallCount
        let verifyCount = await action.verifyCallCount
        let alarmCalled = await tracker.called

        #expect(executeCount == 2)
        #expect(verifyCount == 2)
        #expect(alarmCalled == false)
    }

    @Test("verify false both times → execute twice, alarm once")
    func failureBothAttempts() async {
        let action = MockAction()
        await action.setVerifyResults([false, false])
        let tracker = AlarmTracker()

        await monitorWithRetry(
            action,
            retryDelay: .seconds(0),
            sleep: { _ in },
            onFinalFailure: { await tracker.markCalled() }
        )

        let executeCount = await action.executeCallCount
        let verifyCount = await action.verifyCallCount
        let alarmCalled = await tracker.called

        #expect(executeCount == 2)
        #expect(verifyCount == 2)
        #expect(alarmCalled == true)
    }

    @Test("verify throws (both times) → no alarm")
    func verifyThrowsNoAlarm() async {
        let action = MockAction()
        await action.setShouldVerifyThrow(true)
        let tracker = AlarmTracker()

        await monitorWithRetry(
            action,
            retryDelay: .seconds(0),
            sleep: { _ in },
            onFinalFailure: { await tracker.markCalled() }
        )

        let executeCount = await action.executeCallCount
        let verifyCount = await action.verifyCallCount
        let alarmCalled = await tracker.called

        #expect(executeCount == 2)
        #expect(verifyCount == 2)
        #expect(alarmCalled == false)
    }

    @Test("execute throws but verify eventually true → no alarm")
    func executeThrowsButVerifySucceeds() async {
        let action = MockAction()
        await action.setShouldExecuteThrow(true)
        await action.setVerifyResults([false, true])
        let tracker = AlarmTracker()

        await monitorWithRetry(
            action,
            retryDelay: .seconds(0),
            sleep: { _ in },
            onFinalFailure: { await tracker.markCalled() }
        )

        let executeCount = await action.executeCallCount
        let verifyCount = await action.verifyCallCount
        let alarmCalled = await tracker.called

        #expect(executeCount == 2)
        #expect(verifyCount == 2)
        #expect(alarmCalled == false)
    }
}

// Helper extension for setting mock state
extension SafetyMonitorTests.MockAction {
    func setVerifyResults(_ results: [Bool]) {
        verifyResults = results
    }

    func setShouldExecuteThrow(_ should: Bool) {
        shouldExecuteThrow = should
    }

    func setShouldVerifyThrow(_ should: Bool) {
        shouldVerifyThrow = should
    }
}
