import XCTest
@testable import HearthKit

private actor DoorGateSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() {
        signaled = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
    func wait() async {
        if signaled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
private actor DoorGateEvents {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

final class HaDoorServiceGateTests: XCTestCase {
    private func directory() -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }
        return value
    }

    func testPausedOpenTransportCompletesBeforeOwnedStopCanEnterTransportThroughAnotherHandle() async throws {
        let directory = directory()
        let started = DoorGateSignal(), resume = DoorGateSignal(), waiting = DoorGateSignal()
        let events = DoorGateEvents()
        let open = Task {
            try await HaDoorServiceGate(directory: directory, entityID: "cover.garage").dispatch(isAuthorized: { true }) {
                await events.append("open-start")
                await started.signal()
                await resume.wait()
                await events.append("open-end")
            }
        }
        await started.wait()
        let stop = Task {
            try await HaDoorServiceGate(directory: directory, entityID: "cover.garage",
                onContention: { Task { await waiting.signal() } }).dispatch(isAuthorized: { true }) {
                    await events.append("stop")
                }
        }
        await waiting.wait()
        await resume.signal()
        _ = try await open.value
        _ = try await stop.value
        let actual = await events.snapshot()
        XCTAssertEqual(actual, ["open-start", "open-end", "stop"])
    }

    func testRevokedOperationNeverEntersTheBodyAfterGateAcquisition() async throws {
        let events = DoorGateEvents()
        do {
            try await HaDoorServiceGate(directory: directory(), entityID: "cover.garage").dispatch(isAuthorized: { false }) {
                await events.append("old-open")
            }
            XCTFail("A replaced operation must fail authorization at dispatch")
        } catch {}
        let actual = await events.snapshot()
        XCTAssertTrue(actual.isEmpty)
    }

    func testCancellationWhileWaitingNeverSendsAndHolderReleaseAllowsANewCommand() async throws {
        let directory = directory(), started = DoorGateSignal(), resume = DoorGateSignal(), waiting = DoorGateSignal()
        let events = DoorGateEvents()
        let holder = Task {
            try await HaDoorServiceGate(directory: directory, entityID: "cover.garage").dispatch(isAuthorized: { true }) {
                await started.signal()
                await resume.wait()
            }
        }
        await started.wait()
        let cancelled = Task {
            try await HaDoorServiceGate(directory: directory, entityID: "cover.garage",
                onContention: { Task { await waiting.signal() } }).dispatch(isAuthorized: { true }) {
                    await events.append("cancelled-body")
                }
        }
        await waiting.wait()
        cancelled.cancel()
        _ = try? await cancelled.value
        await resume.signal()
        _ = try await holder.value
        try await HaDoorServiceGate(directory: directory, entityID: "cover.garage").dispatch(isAuthorized: { true }) {
            await events.append("new-body")
        }
        let actual = await events.snapshot()
        XCTAssertEqual(actual, ["new-body"])
    }
}
