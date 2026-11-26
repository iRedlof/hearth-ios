import Foundation
import XCTest
@testable import HearthKit

final class CpOwnedObservationTests: XCTestCase {
    func testProfileAuthorityRequiresExactPositiveIntegerAndNoProviderRefusal() throws {
        let valid = try cpOwnedProfile("{\"user\":{\"userId\":17,\"email\":\"fixture@example.invalid\"}}")
        XCTAssertEqual(valid.userId, 17)
        for raw in [
            "{\"error\":\"refused\",\"user\":{\"userId\":17}}",
            "{\"user\":{\"error_message\":\"refused\",\"userId\":17}}",
            "{\"user\":{\"userId\":true}}", "{\"user\":{\"userId\":1.5}}", "{\"user\":{\"userId\":0}}"
        ] { XCTAssertThrowsError(try cpOwnedProfile(raw)) }
    }

    func testDiscoveryRejectsMalformedStationIdentityBeforeLocationCanBeSelected() throws {
        let valid = try cpOwnedStations("{\"map_data\":{\"stations\":[{\"device_id\":17,\"lat\":47.6,\"lon\":-122.3}]}}")
        XCTAssertEqual(valid.map(\.deviceId), [17])
        for rawID in ["true", "1.5", "0", "\"17\"", "9223372036854775808"] {
            XCTAssertThrowsError(try cpOwnedStations("{\"map_data\":{\"stations\":[{\"device_id\":\(rawID),\"lat\":47.6,\"lon\":-122.3}]}}"))
        }
        for raw in [
            "{\"error\":\"refused\",\"map_data\":{\"stations\":[]}}",
            "{\"map_data\":{\"error_message\":\"refused\",\"stations\":[]}}",
            "{\"map_data\":{\"stations\":[{\"device_id\":17,\"lat\":\"47.6\",\"lon\":-122.3}]}}",
            "{\"map_data\":{\"stations\":[{\"device_id\":17,\"lat\":100,\"lon\":-122.3}]}}"
        ] { XCTAssertThrowsError(try cpOwnedStations(raw)) }
    }

    func testMalformedChargingSupportFlagsCannotGrantStopAuthority() throws {
        let raw = "{\"user_status\":{\"charging\":{\"state\":\"CHARGING\",\"sessionId\":42}}}"
        for fields in ["\"stop_charge_supported\":2", "\"stop_charge_supported\":\"true\"",
                       "\"stop_charge_supported\":true,\"enable_stop_charging\":\"false\""] {
            let value = try cpOwnedObservation(statusJson: raw,
                details: CpDetailEvidence(chargingSessionID: 42,
                    chargingJson: "{\"charging_status\":{\"session_id\":42,\(fields)}}"))
            XCTAssertFalse(value.provider.charging?.canStop == true)
        }
    }
    private func status(_ phase: String = "WAITING", ids: [Int64] = [11, 22],
                        token: String? = nil, device: Int64 = 11, port: Int = 2,
                        start: Int64 = 100, duration: Int64 = 300, session: Int64? = nil) -> String {
        var state: [String: Any] = ["state": phase]
        if let token {
            state["token"] = token; state["deviceId"] = device; state["portNo"] = port
            state["startTimeUTC"] = start; state["duration"] = duration
        }
        var us: [String: Any] = ["waitlist": ["state": state, "stations": ids.map { ["deviceId": $0] }]]
        if let session { us["charging"] = ["sessionId": session, "state": "CHARGING"] }
        let data = try! JSONSerialization.data(withJSONObject: ["user_status": us], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    func testMissingStatusCannotProveAnEmptyQueue() {
        for raw in ["{}", "{\"user_status\":{}}", "not json"] {
            XCTAssertThrowsError(try cpOwnedObservation(statusJson: raw)) {
                XCTAssertEqual($0 as? CpObservationError, .malformed)
            }
        }
    }

    func testExplicitEmptyQueueIsKnownAndHasNoAssignment() throws {
        let value = try cpOwnedObservation(statusJson: status("NOT_QUEUED", ids: []))
        XCTAssertTrue(value.identity.queueKnown)
        XCTAssertFalse(value.identity.queued)
        XCTAssertEqual(value.provider.waitlist, .notQueued)
        XCTAssertNil(value.identity.token)
    }

    func testExactStringNotQueuedIsPositiveIdleEvidence() throws {
        for raw in [
            "{\"user_status\":{\"waitlist\":{\"state\":\"NOT_QUEUED\",\"stations\":[]}}}",
            "{\"user_status\":{\"waitlist\":{\"state\":\"NOT_QUEUED\"}}}"
        ] {
            let value = try cpOwnedObservation(statusJson: raw)
            XCTAssertEqual(value.identity.phase, "NOT_QUEUED")
            XCTAssertEqual(value.identity.stationIDs, [])
            XCTAssertEqual(value.provider.waitlist, .notQueued)
        }
    }

    func testMalformedStringStatesAndRefusalCannotProveEmptyQueue() {
        for raw in [
            "{\"user_status\":{\"waitlist\":{\"state\":\"\"}}}",
            "{\"user_status\":{\"waitlist\":{\"state\":\"FUTURE_PROVIDER_PHASE\"}}}",
            "{\"user_status\":{\"waitlist\":{\"state\":\"PASS\"}}}",
            "{\"user_status\":{\"waitlist\":{\"state\":null}}}",
            "{\"user_status\":{\"waitlist\":{\"state\":false}}}",
            "{\"user_status\":{\"error\":\"refused\",\"waitlist\":{\"state\":\"NOT_QUEUED\"}}}",
            "{\"user_status\":{\"waitlist\":{\"error_message\":\"refused\",\"state\":\"NOT_QUEUED\"}}}"
        ] { XCTAssertThrowsError(try cpOwnedObservation(statusJson: raw)) }
    }

    func testUnknownPhaseIsNotEmptyOrEligibleMembership() throws {
        let value = try cpOwnedObservation(statusJson: status("FUTURE_PROVIDER_PHASE"))
        XCTAssertEqual(value.identity.phase, "UNKNOWN")
        XCTAssertFalse(value.identity.queueKnown)
        XCTAssertFalse(value.identity.queued)
    }

    func testMembershipIsCanonicalAndPlaceIsOnlyPresentation() throws {
        let a = try cpOwnedObservation(statusJson: status(ids: [22, 11]), inlineJson: "{\"positionInline\":1}")
        let b = try cpOwnedObservation(statusJson: status(ids: [11, 22]), inlineJson: "{\"positionInline\":9}")
        XCTAssertEqual(a.identity.stationIDs, [11, 22])
        XCTAssertEqual(a.identity, b.identity)
        XCTAssertNotEqual(a.provider.waitlist, b.provider.waitlist)
    }

    func testEqualStationCountDoesNotMeanEqualMembership() throws {
        let a = try cpOwnedObservation(statusJson: status(ids: [11, 22]))
        let b = try cpOwnedObservation(statusJson: status(ids: [33, 44]))
        XCTAssertNotEqual(a.identity, b.identity)
    }

    func testEachPrivateAssignmentFieldChangesIdentity() throws {
        let original = try cpOwnedObservation(statusJson: status("ACCEPT_PENDING", token: "private-offer-a"))
        let changed = [
            status("ACCEPT_PENDING", token: "private-offer-b"),
            status("ACCEPT_PENDING", token: "private-offer-a", device: 22),
            status("ACCEPT_PENDING", token: "private-offer-a", port: 3),
            status("ACCEPT_PENDING", token: "private-offer-a", start: 101),
            status("ACCEPT_PENDING", token: "private-offer-a", duration: 301),
            status("PENDING_PLUG_IN", token: "private-offer-a"),
        ]
        for raw in changed {
            XCTAssertNotEqual(original.identity, try cpOwnedObservation(statusJson: raw).identity)
        }
        XCTAssertEqual(original.identity.deadlineMs, 400_000)
    }

    func testAllowanceBelongsToExactRequestedToken() {
        XCTAssertThrowsError(try cpOwnedObservation(statusJson: status("PENDING_PLUG_IN", token: "offer-b"),
            details: CpDetailEvidence(allowanceToken: "offer-a", allowanceJson: "{\"response\":{\"remainingSnoozeCount\":1}}"))) {
            XCTAssertEqual($0 as? CpObservationError, .detailsChanged)
        }
    }

    func testUnknownAllowanceRemainsDifferentFromZero() throws {
        let raw = status("PENDING_PLUG_IN", token: "offer")
        let unknown = try cpOwnedObservation(statusJson: raw)
        let zero = try cpOwnedObservation(statusJson: raw,
            details: CpDetailEvidence(allowanceToken: "offer", allowanceJson: "{\"response\":{\"remainingSnoozeCount\":0}}"))
        XCTAssertNil(unknown.provider.snoozesLeft)
        XCTAssertEqual(zero.provider.snoozesLeft, 0)
    }

    func testChargingDetailCannotReplaceRenderedSession() {
        XCTAssertThrowsError(try cpOwnedObservation(statusJson: status("CHARGING", session: 42),
            details: CpDetailEvidence(chargingSessionID: 42,
                chargingJson: "{\"charging_status\":{\"session_id\":43,\"stop_charge_supported\":true}}"))) {
            XCTAssertEqual($0 as? CpObservationError, .detailsChanged)
        }
    }

    func testChargingIdentitySurvivesUnknownDetailsWithoutStopAuthority() throws {
        let value = try cpOwnedObservation(statusJson: status("CHARGING", session: 42))
        XCTAssertEqual(value.identity.sessionID, 42)
        XCTAssertEqual(value.provider.charging?.sessionId, 42)
        XCTAssertEqual(value.provider.charging?.canStop, false)
    }

    func testOverflowingDeadlineIsRejectedBeforeForgivingPresentationParser() {
        XCTAssertThrowsError(try cpOwnedObservation(statusJson: status("ACCEPT_PENDING", token: "offer",
            start: Int64.max, duration: 300))) {
            XCTAssertEqual($0 as? CpObservationError, .malformed)
        }
    }

    func testBooleanStationIdentityIsRejected() {
        XCTAssertThrowsError(try cpOwnedObservation(statusJson:
            "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"WAITING\"},\"stations\":[{\"deviceId\":true}]}}}")) {
            XCTAssertEqual($0 as? CpObservationError, .malformed)
        }
    }

    func testExplicitProviderErrorCannotIssueObservationEvenWithValidStatus() {
        let good = status("NOT_QUEUED", ids: [])
        for key in ["error", "error_message"] {
            var root = try! JSONSerialization.jsonObject(with: Data(good.utf8)) as! [String: Any]
            root[key] = "refused"
            let raw = String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
            XCTAssertThrowsError(try cpOwnedObservation(statusJson: raw))
        }
    }

    func testMalformedChargingAndWaitlistFieldsNeverFallThroughToEmpty() {
        let malformed = [
            "\"charging\":false", "\"charging\":42", "\"charging\":{}",
            "\"charging\":{\"sessionId\":true,\"state\":\"CHARGING\"}",
            "\"charging\":{\"sessionId\":42,\"state\":42}",
            "\"waitlist\":false", "\"waitlist\":{\"state\":42}",
        ]
        for field in malformed {
            XCTAssertThrowsError(try cpOwnedObservation(statusJson: "{\"user_status\":{\(field)}}"))
        }
    }

    func testRepeatedValidProviderStationMembershipHasTheSameCanonicalIdentity() throws {
        XCTAssertEqual(try cpOwnedObservation(statusJson: status(ids: [11, 11])).identity.stationIDs, [11])
    }

    func testTokenMustBeAStringWhenSupplied() {
        XCTAssertThrowsError(try cpOwnedObservation(statusJson:
            "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"ACCEPT_PENDING\",\"token\":true},\"stations\":[]}}}"))
    }

    func testAllowanceWithoutExactRequestedTokenOrWithProviderErrorRemainsUnknown() throws {
        let raw = status("PENDING_PLUG_IN", token: "offer-b")
        let unowned = try cpOwnedObservation(statusJson: raw,
            details: CpDetailEvidence(allowanceJson: "{\"response\":{\"remainingSnoozeCount\":1}}"))
        XCTAssertNil(unowned.provider.snoozesLeft)
        for error in ["\"error\":\"denied\",", "\"error_message\":\"denied\","] {
            let value = try cpOwnedObservation(statusJson: raw,
                details: CpDetailEvidence(allowanceToken: "offer-b",
                    allowanceJson: "{\(error)\"response\":{\"remainingSnoozeCount\":1}}"))
            XCTAssertNil(value.provider.snoozesLeft)
        }
    }

    func testChargingDetailRequiresExactRequestAttributionAndNoRootRefusalForStop() throws {
        let raw = status("CHARGING", session: 42)
        let detail = "{\"charging_status\":{\"session_id\":42,\"stop_charge_supported\":true}}"
        let unattributed = try cpOwnedObservation(statusJson: raw,
            details: CpDetailEvidence(chargingJson: detail))
        XCTAssertEqual(unattributed.provider.charging?.canStop, false)
        let refused = try cpOwnedObservation(statusJson: raw,
            details: CpDetailEvidence(chargingSessionID: 42,
                chargingJson: "{\"error\":\"denied\",\"charging_status\":{\"session_id\":42,\"stop_charge_supported\":true}}"))
        XCTAssertEqual(refused.provider.charging?.canStop, false)
    }
}
