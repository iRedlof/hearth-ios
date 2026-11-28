import Foundation
import XCTest
@testable import HearthKit

/// Covers the ChargePoint action fix: a rendered button stays valid across a read that returns the
/// same observed identity (so the tap is accepted), is refused with a surviving reason when the
/// offer/phase changes, needs only the fields the request actually uses, treats an entry created in
/// another app as actionable, and records every attempt for Diagnostics without a secret.
final class CpActionGateTests: XCTestCase {
    private let now = CpStoreFixture.now

    private func store(armed: Bool = true) throws -> CpStateStore {
        let value = CpStateStore(directory: try CpStoreFixture.directory(self))
        _ = try value.bootstrap(legacy: CpLegacyState(session: CpStoreFixture.session,
            location: CpStoreFixture.location, runWire: armed ? "1|0|0|7|0|||" : "0|0|0|7|0|||"), now: now)
        return value
    }

    /// An ACCEPT_PENDING offer with full fields. `ids` default to stations NOT in the saved location
    /// [1,2], so these also exercise an entry created elsewhere.
    private func offer(_ phase: String = "ACCEPT_PENDING", token: String = "offer-1",
                       ids: [Int64] = [13104611, 16235001], device: Int64 = 16235001,
                       port: Int = 1, start: Int64 = 999, duration: Int64 = 1200) throws -> CpObservation {
        let state: [String: Any] = ["state": phase, "token": token, "deviceId": device, "portNo": port,
                                    "startTimeUTC": start, "duration": duration]
        let raw = String(decoding: try JSONSerialization.data(withJSONObject:
            ["user_status": ["waitlist": ["state": state, "stations": ids.map { ["deviceId": $0] }]]]), as: UTF8.self)
        return try cpOwnedObservation(statusJson: raw)
    }

    private func observed(_ store: CpStateStore, _ value: CpObservation, at time: Date? = nil) throws -> CpStoreSnapshot {
        let time = time ?? now
        let owner = try XCTUnwrap(store.beginRead(expected: store.snapshot(now: time).context, now: time))
        return try XCTUnwrap(store.commitObservation(owner: owner, observation: value, observedAt: time, now: time))
    }

    private func claimedOwner(_ result: CpClaimResult) throws -> CpOperationOwner {
        guard case let .claimed(value) = result else { throw XCTSkip("expected claimed, got \(result)") }
        return value
    }

    // MARK: - 1. Button stays valid across an unchanged read

    func testButtonFromObservationStaysValidAfterIdenticalRead() throws {
        let value = try store()
        let evidence = try offer()
        let drawn = try XCTUnwrap(observed(value, evidence).renderedOrigin)
        // A background status refresh returns the SAME offer identity between drawing and tapping.
        let afterRead = try XCTUnwrap(observed(value, evidence, at: now.addingTimeInterval(5)).renderedOrigin)
        XCTAssertEqual(drawn, afterRead, "An unchanged read must not rotate the identity nonces")
        if case .rejected = try value.claim(origin: drawn, action: .accept, now: now.addingTimeInterval(5)) {
            XCTFail("A button drawn from an unchanged offer must still be accepted")
        }
    }

    // MARK: - 2. Changed offer / phase refuses the stale button, with a surviving reason

    func testButtonFromObservationIsRefusedAfterDifferentOfferWithSurvivingReason() throws {
        for changed in [try offer(token: "offer-2"), try offer("PENDING_PLUG_IN")] {
            let value = try store()
            let drawn = try XCTUnwrap(observed(value, offer()).renderedOrigin)
            _ = try observed(value, changed, at: now.addingTimeInterval(2))   // the offer/phase moved on
            XCTAssertEqual(try value.claim(origin: drawn, action: .accept, now: now.addingTimeInterval(2)),
                           .rejected(.detailsChanged))
            // A record survives so the widget can say what happened, and it names the real reason.
            let record = try XCTUnwrap(try value.snapshot(now: now.addingTimeInterval(2)).lastAction)
            XCTAssertEqual(record.action, "accept")
            XCTAssertFalse(record.requestSent)
            XCTAssertEqual(record.outcome, "Button was out of date")
        }
    }

    // MARK: - 3. Entry created elsewhere is actionable (stations not in the saved location)

    func testAcceptAndLeaveWorkForAnEntryCreatedInAnotherApp() throws {
        // Each claim leaves a pending operation, so a separate store isolates accept from leave.
        let accepting = try store()
        let offered = try observed(accepting, try offer())
        XCTAssertFalse(try offered.displaySnapshot(now: now).keys.isEmpty, "External entry must keep its keys")
        XCTAssertNotNil(try? claimedOwner(accepting.claim(origin: XCTUnwrap(offered.renderedOrigin), action: .accept, now: now)))

        let leaving = try store()
        let queued = try observed(leaving, try offer("WAITING", ids: [98765]))
        XCTAssertFalse(try queued.displaySnapshot(now: now).keys.isEmpty, "External queue must keep its keys")
        XCTAssertNotNil(try? claimedOwner(leaving.claim(origin: XCTUnwrap(queued.renderedOrigin), action: .leave, now: now)))
    }

    /// The account-wide snooze countdown (PASS, no stations, no device) is still not actionable.
    func testAccountWideSnoozeCountdownStaysNonActionable() throws {
        let value = try store(armed: false)
        let evidence = try cpOwnedObservation(statusJson: """
            {"user_status":{"waitlist":{"state":{"state":"PASS","startTimeUTC":999,"duration":301,"autoSnooze":true},"stations":[]}}}
            """)
        let snapshot = try observed(value, evidence)
        XCTAssertEqual(try value.claim(origin: XCTUnwrap(snapshot.renderedOrigin), action: .leave, now: now),
                       .rejected(.detailsChanged))
    }

    // MARK: - 4. Require only what the request uses

    func testAcceptIsAllowedWhenTheReplyOmitsDeviceportAndToken() throws {
        // A realistic ACCEPT_PENDING that carries no deviceId/portNo/token/deadline in its state. The
        // acceptV2 request uses none of those, so the tap must still be accepted (Android parity).
        let value = try store()
        let evidence = try cpOwnedObservation(statusJson:
            "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"ACCEPT_PENDING\"},\"stations\":[{\"deviceId\":55}]}}}")
        XCTAssertNil(evidence.identity.deviceID)
        XCTAssertNil(evidence.identity.port)
        XCTAssertNil(evidence.identity.token)
        let snapshot = try observed(value, evidence)
        XCTAssertNotNil(try? claimedOwner(value.claim(origin: XCTUnwrap(snapshot.renderedOrigin), action: .accept, now: now)))
    }

    // MARK: - 5. Refused / failed actions leave a reason that survives one further read

    func testRefusalReasonSurvivesTheNextIdenticalRead() throws {
        let value = try store()
        let evidence = try offer()
        let origin = try XCTUnwrap(observed(value, evidence).renderedOrigin)
        try value.recordFeedback(origin: origin, feedback: .unavailable, now: now)   // a remote failure
        let afterRead = try observed(value, evidence, at: now.addingTimeInterval(3)) // a plain refresh
        XCTAssertEqual(afterRead.ownershipFeedback, .unavailable, "The reason must survive one further read")
        // And it clears once the state the user is looking at actually changes.
        let changed = try observed(value, try offer(token: "offer-2"), at: now.addingTimeInterval(4))
        XCTAssertNil(changed.ownershipFeedback)
    }

    // MARK: - 6. Diagnostics records a sent action and a local drop, without secrets

    func testDiagnosticsRecordsLocalDropWithoutSecrets() throws {
        let value = try store(armed: false)
        // NOT_QUEUED while the button was for an offer → a stale/ not-actionable local drop.
        let origin = try XCTUnwrap(value.snapshot(now: now).renderedOrigin)
        _ = try value.claim(origin: origin, action: .accept, now: now)
        let record = try XCTUnwrap(try value.snapshot(now: now).lastAction)
        XCTAssertEqual(record.action, "accept")
        XCTAssertFalse(record.requestSent)
        XCTAssertNil(record.host)
        XCTAssertFalse(record.outcome.contains(CpStoreFixture.session.token))
        XCTAssertFalse(record.outcome.contains("@"))
    }
}
