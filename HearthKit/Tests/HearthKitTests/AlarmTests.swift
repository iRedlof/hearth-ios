import XCTest
@testable import HearthKit

private func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
    return g.date(from: s)!
}

final class AlarmStateTests: XCTestCase {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let us = Locale(identifier: "en_US")

    func testParsesHomeAssistantState() {
        let s = AlarmState.fromJson(#"{"entity_id":"alarm_control_panel.x","state":"armed_home","last_changed":"2026-10-12T16:42:00.123456+00:00"}"#)
        XCTAssertEqual(s?.state, "armed_home")
        XCTAssertNotNil(s?.lastChanged)
        XCTAssertLessThan(abs(s!.lastChanged!.timeIntervalSince(iso("2026-10-12T16:42:00Z"))), 1)
    }

    func testGarbageIsNotAState() {
        XCTAssertNil(AlarmState.fromJson("<html>502</html>"))
        XCTAssertNil(AlarmState.fromJson(#"{"message":"Entity not found."}"#))
    }

    func testEveryStateReadsHonestly() {
        XCTAssertEqual(statusFor("disarmed"), StatusView("Disarmed", .calm))
        XCTAssertEqual(statusFor("armed_home"), StatusView("Armed home", .home))
        XCTAssertEqual(statusFor("armed_away"), StatusView("Armed away", .away))
        XCTAssertEqual(statusFor("arming").tone, .busy)
        XCTAssertEqual(statusFor("triggered").tone, .alert)
        XCTAssertEqual(statusFor("unavailable"), StatusView("Unavailable", .unknown))
        XCTAssertEqual(statusFor(nil), StatusView("—", .unknown))
    }

    func testSinceReadsNaturally() {
        let now = iso("2026-10-12T20:00:00Z")
        XCTAssertEqual(sinceLabel(iso("2026-10-12T16:42:00Z"), now: now, zone: zone, locale: us), "since 9:42 AM")
        XCTAssertEqual(sinceLabel(iso("2026-10-11T04:42:00Z"), now: now, zone: zone, locale: us), "since Sat 9:42 PM")
        XCTAssertEqual(sinceLabel(iso("2026-10-01T16:00:00Z"), now: now, zone: zone, locale: us), "since Oct 1")
        XCTAssertNil(sinceLabel(nil, now: now, zone: zone, locale: us))
    }
}

final class CardViewTests: XCTestCase {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let us = Locale(identifier: "en_US")
    lazy var now = iso("2026-10-12T20:00:00Z")
    lazy var nineFortyTwo = iso("2026-10-12T16:42:00Z")

    func testLiveStateWithWhenItChanged() {
        XCTAssertEqual(cardFor("armed_away", error: nil, changedAt: nineFortyTwo, checkedAt: now, now: now, zone: zone, locale: us),
                       CardView("Armed away", .away, "Armed at 9:42 AM"))
        XCTAssertEqual(cardFor("disarmed", error: nil, changedAt: nineFortyTwo, checkedAt: now, now: now, zone: zone, locale: us),
                       CardView("Disarmed", .calm, "Disarmed at 9:42 AM"))
        XCTAssertEqual(cardFor("arming", error: nil, changedAt: nineFortyTwo, checkedAt: now, now: now, zone: zone, locale: us),
                       CardView("Arming…", .busy, "Exit delay"))
        XCTAssertEqual(changedLabel("Armed", at: iso("2026-10-11T04:42:00Z"), now: now, zone: zone, locale: us), "Armed Sat 9:42 PM")
    }

    func testEntryAndExitDelaysReadCleanly() {
        XCTAssertEqual(cardFor("arming", error: nil, changedAt: nineFortyTwo, checkedAt: now, now: now, zone: zone, locale: us).detail, "Exit delay")
        XCTAssertEqual(cardFor("pending", error: nil, changedAt: nineFortyTwo, checkedAt: now, now: now, zone: zone, locale: us).detail, "Entry delay")
    }

    func testOfflineKeepsLastStateGreyed() {
        XCTAssertEqual(cardFor("armed_away", error: "Can't reach Home Assistant", changedAt: nineFortyTwo, checkedAt: nineFortyTwo, now: now, zone: zone, locale: us),
                       CardView("Armed away", .unknown, "Can't reach Home Assistant\nlast checked 9:42 AM"))
        XCTAssertEqual(cardFor(nil, error: "Can't reach Home Assistant", changedAt: nil, checkedAt: nil, now: now, zone: zone, locale: us),
                       CardView("—", .unknown, "Can't reach Home Assistant"))
    }

    func testNotSetUpSaysSo() {
        XCTAssertEqual(cardFor(nil, error: "Set up the widget: tap to open", changedAt: nil, checkedAt: nil, now: now, zone: zone, locale: us),
                       CardView("Set up", .unknown, "Tap to connect"))
    }

    func testStaleOnlyWhileShowingLastKnown() {
        XCTAssertTrue(alarmStale("armed_away", "Can't reach Home Assistant"))
        XCTAssertFalse(alarmStale(nil, "Can't reach Home Assistant"))
        XCTAssertFalse(alarmStale("disarmed", nil))
        XCTAssertFalse(alarmStale("armed_home", "Set up the widget: tap to open"))
    }
}

final class AlarmActionsTests: XCTestCase {
    func testOnlyTheButtonsThatMakeSense() {
        XCTAssertEqual(actionsFor("disarmed"), [.armHome, .armAway])
        for s in ["armed_home", "armed_away", "arming", "disarming", "pending", "triggered"] {
            XCTAssertEqual(actionsFor(s), [.disarm], s)
        }
        XCTAssertTrue(actionsFor(nil).isEmpty)
        XCTAssertTrue(actionsFor("unavailable").isEmpty)
    }

    func testDoorReadsHonestly() {
        XCTAssertEqual(lockStatusFor("locked"), LockView("Locked", true))
        XCTAssertEqual(lockStatusFor("unlocked"), LockView("Unlocked", false))
        XCTAssertEqual(lockStatusFor("jammed"), LockView("Jammed", false))
        XCTAssertEqual(lockStatusFor("locking"), LockView("Locking…", nil))
        XCTAssertEqual(lockStatusFor("unavailable"), LockView("Unavailable", nil))
        XCTAssertEqual(lockStatusFor(nil), LockView("—", nil))
    }

    func testOneLockButtonThatMakesSense() {
        XCTAssertEqual(lockActionFor("locked"), .unlock)
        XCTAssertEqual(lockActionFor("unlocked"), .lock)
        XCTAssertEqual(lockActionFor("jammed"), .lock)
        XCTAssertNil(lockActionFor("locking"))
        XCTAssertNil(lockActionFor("unavailable"))
    }
}

final class BeaconAlarmTests: XCTestCase {
    func testTonePerState() {
        XCTAssertEqual(beaconAlarmPair("disarmed", stale: false), .blue)
        XCTAssertEqual(beaconAlarmPair("armed_home", stale: false), .red)
        XCTAssertEqual(beaconAlarmPair("armed_away", stale: false), .red)
        XCTAssertEqual(beaconAlarmPair("triggered", stale: false), .triggered)
        XCTAssertEqual(beaconAlarmPair("triggered", stale: false).fillARGB, 0xFFF49283)
        XCTAssertEqual(beaconAlarmPair("armed_away", stale: true), .offline)   // stale overrides
        XCTAssertEqual(beaconAlarmPair(nil, stale: false), .offline)
    }

    func testGlyphPerState() {
        XCTAssertEqual(beaconAlarmGlyph(statusFor("disarmed").tone), .off)
        XCTAssertEqual(beaconAlarmGlyph(statusFor("armed_home").tone), .home)
        XCTAssertEqual(beaconAlarmGlyph(statusFor("armed_away").tone), .lock)
        XCTAssertEqual(beaconAlarmGlyph(statusFor("arming").tone), .lock)
        XCTAssertEqual(beaconAlarmGlyph(statusFor("triggered").tone), .alert)
    }

    func testSnapshotMapping() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!, us = Locale(identifier: "en_US")
        let now = iso("2026-10-12T20:00:00Z")
        let alarm = AlarmState(state: "disarmed", lastChanged: iso("2026-10-12T14:00:00Z"), supportedFeatures: 3)
        let snap = alarmSnapshot(alarm: alarm, lockState: "locked", lockChanged: iso("2026-10-12T02:44:00Z"),
                                 name: "Home", error: nil, checkedAt: now, now: now, zone: zone, locale: us)
        XCTAssertEqual(snap.stateWord, "Disarmed")
        XCTAssertEqual(snap.detail, "Disarmed at 7:00 AM")
        XCTAssertEqual(snap.tone, .blue)
        XCTAssertEqual(snap.glyph, .off)
        XCTAssertEqual(snap.doorState, "Locked")
        XCTAssertEqual(snap.doorLocked, true)
        XCTAssertEqual(snap.actions, [.armHome, .armAway])
    }
}
