import XCTest
@testable import HearthKit

/// The ChargePoint auto-waitlist alert prefs + copy (ported 1:1 from Android `cpAutoShouldNotify` /
/// `cpAutoNote`). Four events are user-gated; the operational ones always fire.
final class CpAlertTests: XCTestCase {
    // MARK: - Gating (mirrors Android cpAutoShouldNotify)

    func testGatedAlertsFollowPrefs() {
        let off = CpAlertPrefs(offer: false, accepted: false, snoozed: false, second: false)
        XCTAssertFalse(cpAlertAllowed(.offer, prefs: off))
        XCTAssertFalse(cpAlertAllowed(.secondOffer, prefs: off))
        XCTAssertFalse(cpAlertAllowed(.accepted, prefs: off))
        XCTAssertFalse(cpAlertAllowed(.snoozed, prefs: off))

        let on = CpAlertPrefs()
        XCTAssertTrue(cpAlertAllowed(.offer, prefs: on))
        XCTAssertTrue(cpAlertAllowed(.secondOffer, prefs: on))
        XCTAssertTrue(cpAlertAllowed(.accepted, prefs: on))
        XCTAssertTrue(cpAlertAllowed(.snoozed, prefs: on))
    }

    func testOperationalAlertsAlwaysFire() {
        let off = CpAlertPrefs(offer: false, accepted: false, snoozed: false, second: false)
        for alert in [CpAlert.driveNow, .failed, .signedOut, .done] {
            XCTAssertTrue(cpAlertAllowed(alert, prefs: off), "\(alert) must always alert")
        }
    }

    func testPrefsDefaultOn() {
        let p = CpAlertPrefs()
        XCTAssertTrue(p.offer)
        XCTAssertTrue(p.accepted)
        XCTAssertTrue(p.snoozed)
        XCTAssertTrue(p.second)
    }

    // MARK: - Verbatim copy (ported from Android cpAutoNote), with who/by substitution

    func testContentIsVerbatimWithSubstitutions() {
        let who = "SEA41-29", by = "3:45 PM"
        XCTAssertEqual(cpAlertContent(.offer, who: who, by: by),
                       CpAlertContent(title: "Your turn", body: "I'll accept SEA41-29 at the deadline.", id: "cp.offer"))
        XCTAssertEqual(cpAlertContent(.secondOffer, who: who, by: by),
                       CpAlertContent(title: "Your turn again", body: "I'll accept — no snooze left after this.", id: "cp.second"))
        XCTAssertEqual(cpAlertContent(.accepted, who: who, by: by),
                       CpAlertContent(title: "Accepted SEA41-29", body: "Held — plug in by 3:45 PM. I'll take the next step.", id: "cp.accepted"))
        XCTAssertEqual(cpAlertContent(.snoozed, who: who, by: by),
                       CpAlertContent(title: "Snoozed", body: "Back in line about an hour. Still automating.", id: "cp.snoozed"))
        XCTAssertEqual(cpAlertContent(.driveNow, who: who, by: by),
                       CpAlertContent(title: "🚗 Drive now", body: "Spot held — plug in by 3:45 PM. No snooze left.", id: "cp.driveNow"))
        XCTAssertEqual(cpAlertContent(.failed, who: who, by: by),
                       CpAlertContent(title: "Couldn't do it — your turn", body: "Tap to handle it yourself before 3:45 PM.", id: "cp.failed"))
        XCTAssertEqual(cpAlertContent(.signedOut, who: who, by: by),
                       CpAlertContent(title: "Signed out of ChargePoint", body: "Sign in again to keep the widget live.", id: "cp.signedOut"))
        XCTAssertEqual(cpAlertContent(.done, who: who, by: by),
                       CpAlertContent(title: "Charging — all set", body: "Auto-waitlist done.", id: "cp.done"))
    }

    // MARK: - who/by derived from a userStatus body

    func testSubjectsFallBackWhenNoOffer() {
        let subj = cpAlertSubjects(#"{"user_status":{"waitlist":{"state":{"state":"WAITING"}}}}"#)
        XCTAssertEqual(subj.who, "your charger")
        XCTAssertEqual(subj.by, "the deadline")
    }

    func testSubjectsFillFromOffer() {
        // start+duration give a real deadline; the station name gives a real charger short-name.
        let json = #"{"user_status":{"waitlist":{"state":{"state":"ACCEPT_PENDING","deviceId":16235001,"startTimeUTC":1792372024,"duration":1200,"token":"T0K3N","portNo":1},"stations":[{"deviceId":16235001,"name":"SEA41 SEA41-29 P3"}]}}}"#
        let subj = cpAlertSubjects(json)
        XCTAssertNotEqual(subj.who, "your charger")   // a real charger short-name
        XCTAssertFalse(subj.who.isEmpty)
        XCTAssertNotEqual(subj.by, "the deadline")    // a formatted clock (tz-dependent, so not asserted exactly)
    }
}
