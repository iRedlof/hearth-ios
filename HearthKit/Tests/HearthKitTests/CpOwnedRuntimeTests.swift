import Foundation
import XCTest
@testable import HearthKit

final class CpOwnedRuntimeTests: XCTestCase {
    private func configured(armed: Bool = false) throws -> (CpStateStore, URL) {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpLegacyState(session: CpStoreFixture.session,
            location: CpStoreFixture.location, runWire: armed ? "1|0|0|7|0|||" : "0|0|0|7|0|||"), now: CpStoreFixture.now)
        return (store, directory)
    }

    func testRefreshPublishesTypedOwnedEvidenceAndProviderFailureKeepsOriginalTime() async throws {
        let (store, directory) = try configured()
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        let first = try await runtime.refresh(runAuto: false)
        XCTAssertEqual(first.actionLabel, "Join")
        XCTAssertNotNil(try store.snapshot(now: clock.now).renderedOrigin?.observationID)
        let observedAt = try store.snapshot(now: clock.now).reading?.observedAt
        transport.status = "{}"
        clock.advance(1)
        let failed = try await runtime.refresh(runAuto: false)
        XCTAssertTrue(failed.stale)
        XCTAssertEqual(try store.snapshot(now: clock.now).reading?.observedAt, observedAt)
        XCTAssertNotEqual(failed.actionLabel, "Join")
    }

    func testDuplicateManualJoinDoesNotDispatchAgainAndDoesNotArmAuto() async throws {
        let (store, directory) = try configured()
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        let origin = try XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin)
        _ = try await runtime.perform(origin: origin, action: .join)
        _ = try? await runtime.perform(origin: origin, action: .join)
        XCTAssertEqual(transport.mutations, 1)
        XCTAssertFalse(try store.snapshot(now: clock.now).run.armed)
    }

    func testExplicitJoinAutoDoesNotSwitchToResumeWhenPreflightQueueChanges() async throws {
        let (store, directory) = try configured()
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        let origin = try XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin)
        transport.status = CpRuntimeTransport.waiting
        _ = try? await runtime.setAuto(origin: origin, desired: .join)
        XCTAssertEqual(transport.mutations, 0)
        XCTAssertFalse(try store.snapshot(now: clock.now).run.armed)
    }

    func testAdmittedTransportFailureBecomesUncertainAndNeverReplays() async throws {
        let (store, directory) = try configured(armed: true)
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        let origin = try XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin)
        transport.failMutation = true
        _ = try? await runtime.perform(origin: origin, action: .join)
        let uncertain = try store.snapshot(now: clock.now)
        XCTAssertEqual(uncertain.operation?.stage, .uncertain)
        _ = try? await runtime.perform(origin: origin, action: .join)
        XCTAssertEqual(transport.mutations, 1)
        _ = try await runtime.setAuto(origin: XCTUnwrap(uncertain.renderedOrigin), desired: .pause)
        XCTAssertFalse(try store.snapshot(now: clock.now).run.armed)
        XCTAssertNotNil(try store.snapshot(now: clock.now).operation)
        clock.advance(1)
        _ = try await runtime.refresh(runAuto: false)
        XCTAssertNil(try store.snapshot(now: clock.now).operation)
    }

    func testIdleAutoRefreshDoesNotJoinWithoutExplicitUserJoin() async throws {
        let (store, directory) = try configured(armed: true)
        let transport = CpRuntimeTransport()
        let instant = CpStoreFixture.now
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
        _ = try await runtime.refresh()
        XCTAssertEqual(transport.mutations, 0)
        XCTAssertTrue(try store.snapshot(now: instant).run.armed)
    }

    func testResumeRequiresQueuedObservationAndPreservesSpentSnoozeHistory() async throws {
        let (store, directory) = try configured()
        let transport = CpRuntimeTransport()
        transport.status = CpRuntimeTransport.waiting
        let instant = CpStoreFixture.now
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
        _ = try await runtime.refresh(runAuto: false)
        let origin = try XCTUnwrap(store.snapshot(now: instant).renderedOrigin)
        let resumed = try await runtime.setAuto(origin: origin, desired: .resume)
        XCTAssertTrue(try store.snapshot(now: instant).run.armed)
        XCTAssertEqual(transport.mutations, 0)
        XCTAssertEqual(resumed.activatedMode, try store.snapshot(now: instant).context)
    }

    func testMalformedSuccessfulMutationBodyRetainsAdmittedUncertainty() async throws {
        let (store, directory) = try configured()
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        transport.status = CpRuntimeTransport.offer
        transport.mutationBody = "{\"response\":{}}"
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        let origin = try XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin)
        _ = try await runtime.perform(origin: origin, action: .accept)
        XCTAssertEqual(transport.mutations, 1)
        XCTAssertEqual(try store.snapshot(now: clock.now).operation?.stage, .uncertain)
        XCTAssertEqual(try store.snapshot(now: clock.now).ownershipFeedback, .noResponse)
    }

    func testExplicitNegativeMutationAcknowledgementIsRefusedRatherThanUncertain() async throws {
        let (store, directory) = try configured()
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        transport.status = CpRuntimeTransport.offer
        transport.mutationBody = "{\"result\":false}"
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        _ = try await runtime.perform(origin: XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin), action: .accept)
        XCTAssertNil(try store.snapshot(now: clock.now).operation)
        XCTAssertEqual(try store.snapshot(now: clock.now).ownershipFeedback, .unavailable)
    }

    func testMalformedNestedMutationAcknowledgementRetainsUncertainty() async throws {
        for response in [
            "{\"result\":true,\"response\":{\"success\":2}}",
            "{\"result\":true,\"response\":{\"success\":\"false\"}}",
            "{\"result\":true,\"response\":{\"error\":\"refused\",\"success\":true}}",
            "{\"result\":true,\"response\":false}"
        ] {
            let (store, directory) = try configured()
            let clock = CpFixtureClock()
            let transport = CpRuntimeTransport()
            transport.status = CpRuntimeTransport.offer
            transport.mutationBody = response
            let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
            _ = try await runtime.refresh(runAuto: false)
            _ = try await runtime.perform(origin: XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin), action: .accept)
            XCTAssertEqual(transport.mutations, 1)
            XCTAssertEqual(try store.snapshot(now: clock.now).operation?.stage, .uncertain)
            XCTAssertEqual(try store.snapshot(now: clock.now).ownershipFeedback, .noResponse)
        }
    }

    func testErrorBearingStopReceiptCannotEstablishACommandResult() async throws {
        let (store, directory) = try configured()
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        transport.status = "{\"user_status\":{\"charging\":{\"state\":\"CHARGING\",\"sessionId\":42}}}"
        transport.mutationBody = "{\"error_message\":\"refused\",\"ackId\":44}"
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        _ = try await runtime.perform(origin: XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin), action: .stop)
        XCTAssertEqual(transport.mutations, 1)
        XCTAssertEqual(try store.snapshot(now: clock.now).operation?.stage, .uncertain)
        XCTAssertNil(try store.snapshot(now: clock.now).operation?.acknowledgementID)
    }

    func testAutomaticUncertainAndRefusedAcceptNeverRepeatSameTargetAfterReconciliation() async throws {
        for malformed in [false, true] {
            let (store, directory) = try configured(armed: true)
            let clock = CpFixtureClock()
            let transport = CpRuntimeTransport()
            transport.status = CpRuntimeTransport.offer
            transport.mutationBody = malformed ? "{}" : "{\"result\":false}"
            let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
            _ = try await runtime.refresh()
            clock.advance(1)
            _ = try await runtime.refresh()
            XCTAssertEqual(transport.mutations, 1, "A fresh read must not authorize Auto to retry its failed target")
            let current = try store.snapshot(now: clock.now)
            XCTAssertTrue(current.run.armed)
            XCTAssertEqual(current.run.failedState, "ACCEPT_PENDING")
            XCTAssertNil(current.operation)
        }
    }

    func testAutomaticHeldSnoozeSpendsOneAllowanceAndNeverSnoozesAgain() async throws {
        let (store, directory) = try configured(armed: true)
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        transport.status = CpRuntimeTransport.offer.replacingOccurrences(of: "ACCEPT_PENDING", with: "PENDING_PLUG_IN")
        transport.allowance = 1
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh()
        clock.advance(1)
        _ = try await runtime.refresh()
        XCTAssertEqual(transport.mutations, 1)
        XCTAssertTrue(try store.snapshot(now: clock.now).run.snoozeUsed)
        XCTAssertTrue(try store.snapshot(now: clock.now).run.armed)
    }

    func testAutomaticHeldUnknownAllowanceDoesNotSendSnooze() async throws {
        let (store, directory) = try configured(armed: true)
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        transport.status = CpRuntimeTransport.offer.replacingOccurrences(of: "ACCEPT_PENDING", with: "PENDING_PLUG_IN")
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh()
        XCTAssertEqual(transport.mutations, 0)
        XCTAssertFalse(try store.snapshot(now: clock.now).run.snoozeUsed)
    }

    func testStopAcknowledgement403CannotRefuseAlreadyAdmittedStop() async throws {
        let (store, directory) = try configured()
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        transport.status = "{\"user_status\":{\"charging\":{\"state\":\"CHARGING\",\"sessionId\":42}}}"
        transport.mutationBody = "{\"ackId\":44}"
        transport.acknowledgementStatus = 403
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        _ = try await runtime.perform(origin: XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin), action: .stop)
        XCTAssertEqual(transport.mutations, 1)
        XCTAssertEqual(try store.snapshot(now: clock.now).operation?.stage, .uncertain)
    }

    func testRetiredAutoIntentCannotPublishActivationForExistingArmedReplacement() async throws {
        let (store, directory) = try configured(armed: true)
        let clock = CpFixtureClock()
        let transport = CpRuntimeTransport()
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { clock.now })
        _ = try await runtime.refresh(runAuto: false)
        let old = try XCTUnwrap(store.snapshot(now: clock.now).renderedOrigin)
        _ = try store.edit(expected: CpSettingsOrigin(context: old.context), edit: .signOut, now: clock.now)
        let attempt = try XCTUnwrap(store.beginSignIn(expected: store.snapshot(now: clock.now).settingsOrigin, now: clock.now))
        _ = try store.replaceSession(owner: attempt, candidate: CpStoreFixture.session, now: clock.now)
        _ = try store.edit(expected: store.snapshot(now: clock.now).settingsOrigin, edit: .location(CpStoreFixture.location), now: clock.now)
        let result = try await runtime.setAuto(origin: old, desired: .join)
        XCTAssertNil(result.activatedMode)
        XCTAssertEqual(transport.mutations, 0)
    }
}

private final class CpFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = CpStoreFixture.now
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

private final class CpRuntimeTransport: CpOwnedTransport, @unchecked Sendable {
    static let empty = "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"NOT_QUEUED\"},\"stations\":[]}}}"
    static let waiting = "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"WAITING\"},\"stations\":[{\"deviceId\":1},{\"deviceId\":2}]}}}"
    static let offer = "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"ACCEPT_PENDING\",\"token\":\"offer\",\"deviceId\":1,\"portNo\":1,\"startTimeUTC\":999,\"duration\":61},\"stations\":[{\"deviceId\":1},{\"deviceId\":2}]}}}"
    private let lock = NSLock()
    private var raw = empty
    private var failing = false
    private var count = 0
    private var reply = "{\"result\":true,\"response\":{\"success\":true}}"
    private var left: Int?
    private var ackStatus = 200
    var status: String { get { lock.withLock { raw } } set { lock.withLock { raw = newValue } } }
    var failMutation: Bool { get { lock.withLock { failing } } set { lock.withLock { failing = newValue } } }
    var mutations: Int { lock.withLock { count } }
    var mutationBody: String { get { lock.withLock { reply } } set { lock.withLock { reply = newValue } } }
    var allowance: Int? { get { lock.withLock { left } } set { lock.withLock { left = newValue } } }
    var acknowledgementStatus: Int { get { lock.withLock { ackStatus } } set { lock.withLock { ackStatus = newValue } } }
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        let path = request.url!.path
        let mutates = path.hasSuffix("/join") || path.contains("V2") || path.hasSuffix("/leave") || path.hasSuffix("/stopSession")
        let body: String
        if mutates { body = mutationBody }
        else if path.contains("/get_notification_detail/") {
            body = allowance.map { "{\"response\":{\"remainingSnoozeCount\":\($0)}}" } ?? "{}"
        }
        else if path.hasSuffix("/sessions/42") { body = "{\"charging_status\":{\"session_id\":42,\"stop_charge_supported\":true}}" }
        else if path.hasSuffix("/inlinestatus") { body = "{\"positionInline\":3}" }
        else {
            let object = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            body = object?["user_status"] != nil ? status : "{}"
        }
        return CpRuntimePrepared(url: request.url!, body: body, fail: mutates && failMutation,
            status: path.hasSuffix("/ack") ? acknowledgementStatus : 200) { [self] in
            if mutates { lock.withLock { count += 1 } }
        }
    }
}

private struct CpRuntimePrepared: CpPreparedRequest {
    let url: URL
    let body: String
    let fail: Bool
    var status = 200
    let onStart: @Sendable () -> Void
    func start() { onStart() }
    func cancel() {}
    func response() async throws -> (Data, HTTPURLResponse) {
        if fail { throw URLError(.networkConnectionLost) }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
