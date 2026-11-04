import XCTest
@testable import HearthKit

final class CpPresentationTests: XCTestCase {
    func testFourTimedPhasesTreatNonpositiveTimeAsUnknownWithoutChangingSource() {
        for phase in ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "PASS"] {
            for deadline: Int64 in [0, -1] {
                var value = held(phase)
                value.location = location
                value.waitlist = .inLine(place: nil, state: phase, stations: 1,
                    offer: CpOffer(deviceId: 1, port: 1, charger: "SEA41 - 29 P3", untilMs: deadline), auto: false)
                value.snoozesLeft = 1
                let original = value
                let snapshot = cpSnapshot(value, email: "person@example.invalid", checkedAt: "9:41 AM", now: now)
                XCTAssertEqual(snapshot.sub, "Deadline unknown\nRefresh to check")
                XCTAssertEqual(snapshot.statusDescription, "Deadline unknown. Refresh to check.")
                XCTAssertEqual(snapshot.bigAnswer, "—")
                XCTAssertEqual(snapshot.keys.map(\.command), ["open", "leave"])
                XCTAssertNil(snapshot.deadline)
                XCTAssertNil(snapshot.goTo)
                XCTAssertTrue(snapshot.railNotes.isEmpty)
                XCTAssertEqual(snapshot.checkedAt, "9:41 AM")
                XCTAssertEqual(snapshot.account, "person")
                XCTAssertNil(snapshot.origin)
                XCTAssertEqual(value, original)
                XCTAssertEqual(value.snoozesLeft, 1)
                var expired = value
                expired.account = cpAccount(hasSession: true, expired: false, joinExpired: true)
                XCTAssertTrue(cpSnapshot(expired, email: "person@example.invalid", checkedAt: "9:41 AM",
                                          now: now).keys.isEmpty)
            }
        }
    }

    private func held(_ state: String = "PENDING_PLUG_IN") -> CpState {
        CpState(signedOut: false, account: cpAccount(hasSession: true, expired: false),
                location: nil, now: nil,
                waitlist: .inLine(place: nil, state: state, stations: 1,
                                 offer: CpOffer(deviceId: 1, port: 1, charger: "SEA41 - 29 P3",
                                                untilMs: 1_700_000_600_000), auto: false),
                charging: nil, autoOn: true)
    }

    func testAssignedUnknownSnoozesStillOffersOpenAndLeave() {
        for state in ["PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"] {
            XCTAssertEqual(cpManualKeys(held(state)).map(\.command), ["open", "leave"])
        }
    }

    func testSnapshotRetainsActualFreshnessStamp() {
        var value = held()
        value.location = location
        let snapshot = cpSnapshot(value, email: "person@example.com", checkedAt: "9:41 AM", now: now)
        XCTAssertEqual(snapshot.checkedAt, "9:41 AM")
        XCTAssertEqual(snapshot.account, "person")
        XCTAssertTrue(snapshot.autoOn)
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var location: CpLocation {
        CpLocation(name: "Amazon Day 1", address: "", deviceIds: [1], bounds: cpBounds(lat: 0, lon: 0))
    }

    func testSnoozedSnapshotUsesLiveMapperAndOffersEscape() {
        var value = held("PASS")
        value.location = location
        value.floors = [CpFloor(level: "P3", free: 0, total: 18)]
        let snap = cpSnapshot(value, email: nil, checkedAt: "9:41 AM", now: now)
        XCTAssertEqual(snap.bigAnswer, "Snoozed")
        XCTAssertEqual(snap.keys.map(\.command), ["unsnooze", "leave"])
        XCTAssertEqual(snap.floors, value.floors)
        XCTAssertNotNil(snap.deadline)
    }

    func testPassTimePolicyDistinguishesFutureEqualityPastAndUnknownWithoutDroppingReadings() {
        let future = Int64(now.addingTimeInterval(600).timeIntervalSince1970 * 1000)
        let cases: [(Int64?, Date, String?)] = [
            (future, now, nil),
            (future, now.addingTimeInterval(600), "Time elapsed"),
            (future, now.addingTimeInterval(601), "Time elapsed"),
            (nil, now, "Deadline unknown"), (0, now, "Deadline unknown"), (-1, now, "Deadline unknown")
        ]
        for (until, clock, reason) in cases {
            for armed in [false, true] {
                var state = held("PASS")
                state.location = location
                state.autoOn = armed
                state.floors = [CpFloor(level: "P3", free: 7, total: 18)]
                state.waitlist = .inLine(place: nil, state: "PASS", stations: 1,
                    offer: until.map { CpOffer(deviceId: 0, port: 0, charger: "", untilMs: $0) }, auto: true)
                let original = state
                let snapshot = cpSnapshot(state, email: "person@example.test", checkedAt: "original stamp", now: clock)
                XCTAssertEqual(state, original)
                XCTAssertEqual(snapshot.site, location.title)
                XCTAssertEqual(snapshot.account, "person")
                XCTAssertEqual(snapshot.checkedAt, "original stamp")
                XCTAssertEqual(snapshot.floors, state.floors)
                XCTAssertNil(snapshot.origin)
                XCTAssertNil(snapshot.goTo)
                XCTAssertEqual(snapshot.autoOn, armed)
                XCTAssertFalse(snapshot.keys.contains { $0.command == "snooze" })
                if let reason {
                    XCTAssertEqual(snapshot.bigAnswer, "—")
                    XCTAssertEqual(snapshot.unit, "")
                    XCTAssertNil(snapshot.deadline)
                    XCTAssertTrue(snapshot.railNotes.isEmpty)
                    XCTAssertEqual(snapshot.sub, "\(reason)\nRefresh to check")
                    XCTAssertEqual(snapshot.statusDescription, "\(reason). Refresh to check.")
                    XCTAssertEqual(snapshot.keys.map(\.command), ["open", "leave"])
                    XCTAssertEqual(snapshot.keys.map(\.label), ["Open ChargePoint", "Leave"])
                } else {
                    XCTAssertEqual(snapshot.bigAnswer, "Snoozed")
                    XCTAssertEqual(snapshot.deadline, now.addingTimeInterval(600))
                    XCTAssertEqual(snapshot.sub, "Back in line at \(cpClockString(now.addingTimeInterval(600)))")
                    XCTAssertNil(snapshot.statusDescription)
                    XCTAssertEqual(snapshot.keys.map(\.command), ["unsnooze", "leave"])
                }
            }
        }
    }

    func testPassCleanupNeverReplacesAuthenticationAndChargingPriority() {
        for joinExpired in [false, true] {
            var state = held("PASS")
            state.location = location
            state.signedOut = !joinExpired
            state.account = cpAccount(hasSession: joinExpired, expired: !joinExpired, joinExpired: joinExpired)
            let snapshot = cpSnapshot(state, email: "person@example.test", checkedAt: "old", now: now.addingTimeInterval(700))
            XCTAssertEqual(snapshot.bigAnswer, "Sign in")
            XCTAssertTrue(snapshot.keys.isEmpty)
            XCTAssertNil(snapshot.statusDescription)
        }
        var charging = held("PASS")
        charging.location = location
        charging.charging = CpCharging(sessionId: 9, powerKw: 6.6, energyKwh: 7.4, minutes: 65, canStop: true)
        let snapshot = cpSnapshot(charging, email: nil, checkedAt: "old", now: now.addingTimeInterval(700))
        XCTAssertEqual(snapshot.bigAnswer, "7.4")
        XCTAssertEqual(snapshot.keys.map(\.command), ["stop"])
        XCTAssertNil(snapshot.statusDescription)
    }

    func testChargingSnapshotUsesEnergyAndActualSessionStats() {
        var value = held("CHARGING")
        value.location = location
        value.charging = CpCharging(sessionId: 9, powerKw: 6.6, energyKwh: 7.4, minutes: 65,
                                   canStop: false, miles: 31, vehicle: "Tesla Model Y", charger: "SEA41 - 29 P3")
        let snap = cpSnapshot(value, email: nil, checkedAt: "9:41 AM", now: now)
        XCTAssertEqual(snap.bigAnswer, "7.4")
        XCTAssertEqual(snap.unit, "kWh added")
        XCTAssertEqual(snap.stats.map(\.value), ["31 mi", "1 h 05", "SEA41-29 · P3"])
        XCTAssertEqual(snap.keys.map(\.command), ["open"])
        XCTAssertFalse(snap.autoOn)
    }

    func testMissingCountsNeverClaimZeroFree() {
        var value = held()
        value.location = location
        value.waitlist = .notQueued
        let snap = cpSnapshot(value, email: nil, checkedAt: "9:41 AM", now: now)
        XCTAssertEqual(snap.bigAnswer, "—")
        XCTAssertEqual(snap.unit, "plugs free")
        XCTAssertEqual(snap.sub, "Reading pending")
    }

    func testTimedCompletionAndFaultStatesDoNotLookLikeQueuePositions() {
        for (status, title, keys) in [
            ("CHARGING_FAULT", "Not charging", ["still", "done"]),
            ("DIB_PLUG_OUT", "Unplugged", ["still", "done"]),
            ("PENDING_PLUG_OUT", "Done charging", ["open"]),
            ("OVER_STAYED", "Move your car", ["open"]),
            ("BLOCKED", "Blocked", ["leave"])
        ] {
            var value = held(status)
            value.location = location
            let snap = cpSnapshot(value, email: nil, checkedAt: "9:41 AM", now: now)
            XCTAssertEqual(snap.bigAnswer, title, status)
            XCTAssertEqual(snap.keys.map(\.command), keys, status)
            XCTAssertEqual(snap.goTo, "SEA41 - 29 P3", status)
            if status != "BLOCKED" { XCTAssertNotNil(snap.deadline, status) }
        }
    }

    func testExpiredSnapshotDisplaysElapsedTimeInsteadOfAValidOfferClock() {
        var value = held("ACCEPT_PENDING")
        value.location = location
        let snap = cpSnapshot(value, email: nil, checkedAt: "9:41 AM", now: now.addingTimeInterval(600))
        XCTAssertNil(snap.deadline)
        XCTAssertEqual(snap.sub, "Time elapsed\nRefresh to check")
        XCTAssertEqual(snap.keys.map(\.command), ["open", "leave"])
        XCTAssertNil(snap.goTo)
    }

    func testAutoIsOnlyActiveWhenAccountLocationAndSessionPermitIt() {
        var value = held()
        XCTAssertFalse(cpSnapshot(value, email: nil, checkedAt: "", now: now).autoOn)
        value.location = location
        XCTAssertTrue(cpSnapshot(value, email: nil, checkedAt: "", now: now).autoOn)
        value.account = cpAccount(hasSession: true, expired: false, joinExpired: true)
        XCTAssertFalse(cpSnapshot(value, email: nil, checkedAt: "", now: now).autoOn)
        value.account = cpAccount(hasSession: true, expired: false)
        value.signedOut = true
        XCTAssertFalse(cpSnapshot(value, email: nil, checkedAt: "", now: now).autoOn)
    }

    func testAutoControlSelectsJoinResumePauseAndSetup() {
        var value = held()
        XCTAssertEqual(cpAutoControl(value), .disabled)
        value.location = location
        value.autoOn = false
        XCTAssertEqual(cpAutoControl(value), .resume)
        value.waitlist = .notQueued
        XCTAssertEqual(cpAutoControl(value), .join)
        value.autoOn = true
        XCTAssertEqual(cpAutoControl(value), .stop)
        value.signedOut = true
        XCTAssertEqual(cpAutoControl(value), .signin)
    }

    func testPendingAndFailedCommandsHaveVisibleFeedback() {
        let base = cpSnapshot(held("ACCEPT_PENDING"), email: nil, checkedAt: "", now: now)
        let pending = cpApplyingOperation(base, CpOperation(command: "accept", startedAt: now), now: now)
        XCTAssertEqual(pending.keys.first?.label, "Accepting…")
        let failed = cpApplyingOperation(base, CpOperation(command: "accept", startedAt: now, error: "Offer expired"), now: now)
        XCTAssertEqual(failed.sub, "Offer expired")
        let timedOut = cpApplyingOperation(base, CpOperation(command: "accept", startedAt: now), now: now.addingTimeInterval(121))
        XCTAssertEqual(timedOut.sub, "No response · Refresh to check")
    }

    func testAssignedSnoozeMustBeConfirmed() {
        for state in ["PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"] {
            for allowance in [1, 0, -1] {
                var value = held(state)
                value.snoozesLeft = allowance
                XCTAssertEqual(cpManualKeys(value).map(\.command),
                               allowance > 0 ? ["open", "snooze"] : ["open", "leave"])
            }
        }
    }

    func testOfferOnlyExposesSnoozeWithConfirmedAllowance() {
        for allowance in [nil, -1, 0, 1, 2] as [Int?] {
            var value = held("ACCEPT_PENDING")
            value.snoozesLeft = allowance
            XCTAssertEqual(cpManualKeys(value).map(\.command),
                           (allowance ?? 0) > 0 ? ["accept", "snooze"] : ["accept", "leave"])
        }
    }

    func testCountdownRangeNeverRunsBackwardsAtTheDeadlineBoundary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(cpCountdownInterval(until: now.addingTimeInterval(-1), now: now))
        XCTAssertNil(cpCountdownInterval(until: now, now: now))
        XCTAssertEqual(cpCountdownInterval(until: now.addingTimeInterval(1), now: now),
                       now...now.addingTimeInterval(1))
    }
}
