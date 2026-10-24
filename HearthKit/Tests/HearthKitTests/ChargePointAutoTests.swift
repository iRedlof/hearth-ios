import XCTest
@testable import HearthKit

/// Ports Android ChargePointAutoTest / ChargePointResumeTest / ChargePointArmTest 1:1.
final class ChargePointAutoTests: XCTestCase {
    let armed = CpRun(armed: true, startedAt: 1000)
    let now: Int64 = 1_700_000_000_000
    let m: Int64 = 120_000

    private func decide(_ run: CpRun, _ state: String, _ until: Int64?, _ snoozes: Int?,
                        _ charging: Bool, _ now: Int64? = nil) -> CpAutoStep {
        cpAutoDecide(run, state: state, untilMs: until, snoozesLeft: snoozes,
                     charging: charging, now: now ?? self.now, marginMs: m)
    }

    // 1
    func testNotArmedIsIdle() {
        XCTAssertEqual(decide(CpRun(armed: false), "ACCEPT_PENDING", now + 60_000, 1, false), .idle)
    }
    // 2,3,4,12
    func testOfferTiming() {
        XCTAssertEqual(decide(armed, "ACCEPT_PENDING", now + 600_000, 1, false), .wakeAt(now + 600_000 - m))
        XCTAssertEqual(decide(armed, "ACCEPT_PENDING", now + 90_000, 1, false), .accept(armed))
        XCTAssertEqual(decide(armed, "ACCEPT_PENDING", now - 5_000, 1, false), .accept(armed))
        XCTAssertEqual(decide(armed, "ACCEPT_PENDING", nil, 1, false), .idle)
    }
    // 5,6,7,8,9
    func testHeld() {
        let snoozed = CpRun(armed: true, snoozeUsed: true, startedAt: 1000)
        XCTAssertEqual(decide(armed, "PENDING_PLUG_IN", now + 60_000, 1, false), .snooze(snoozed))
        XCTAssertEqual(decide(armed, "PENDING_PLUG_IN", now + 1_000_000, 1, false), .wakeAt(now + 1_000_000 - m))
        XCTAssertEqual(decide(armed, "DIB_PENDING_PLUG_IN", now + 60_000, 1, false), .snooze(snoozed))
        // no snooze left → drive-now once, then idle
        let drove = CpRun(armed: true, drivePushed: true, startedAt: 1000)
        XCTAssertEqual(decide(armed, "PENDING_PLUG_IN", now + 60_000, 0, false), .alert(.driveNow, drove))
        XCTAssertEqual(decide(drove, "PENDING_PLUG_IN", now + 60_000, 0, false), .idle)
        // won't snooze twice even if CP still reports one available
        let used = CpRun(armed: true, snoozeUsed: true, startedAt: 1000)
        XCTAssertEqual(decide(used, "PENDING_PLUG_IN", now + 60_000, 1, false),
                       .alert(.driveNow, CpRun(armed: true, snoozeUsed: true, drivePushed: true, startedAt: 1000)))
    }
    // 10
    func testOtherStatesIdle() {
        for s in ["PASS", "WAITING", "PENDING", "", "UNKNOWN"] {
            XCTAssertEqual(decide(armed, s, now + 60_000, 1, false), .idle, "state \(s)")
        }
    }
    // 11
    func testChargingEndsRun() {
        XCTAssertEqual(decide(armed, "CHARGING", nil, 0, true), .done)
        XCTAssertEqual(decide(armed, "PENDING_PLUG_IN", nil, 1, true), .done)
    }
    // 13
    func testAfterAct() {
        let before = CpRun(armed: true)
        XCTAssertEqual(cpAfterAct(before, .snooze(before.snoozeUsedCopy()), false), before)
        XCTAssertEqual(cpAfterAct(before, .snooze(before.snoozeUsedCopy()), true), before.snoozeUsedCopy())
        XCTAssertEqual(cpAfterAct(before, .accept(armed), true), armed)
    }
    // 14,15
    func testPauseResume() {
        let run = CpRun(armed: true, snoozeUsed: true, startedAt: 7, offerPushed: true)
        XCTAssertFalse(cpPauseRun(run).armed)
        XCTAssertEqual(cpResumeRun(cpPauseRun(run), nil, 99), run)
        XCTAssertEqual(cpResumeRun(CpRun(), 0, 99), CpRun(armed: true, snoozeUsed: true, startedAt: 99))
    }
    // 16
    func testManualSnoozeSpendsSnooze() {
        for a in [true, false] {
            let r = CpRun(armed: a)
            XCTAssertEqual(cpAfterManual(r, .snooze(600), true), { var x = r; x.snoozeUsed = true; return x }())
            XCTAssertEqual(cpAfterManual(r, .snooze(600), false), r)
            XCTAssertEqual(cpAfterManual(r, .unsnooze, true), r)
        }
    }
    // 17
    func testMergeCantRearmPaused() {
        let before = CpRun(armed: true, startedAt: 1000)
        let step = CpAutoStep.snooze(CpRun(armed: true, snoozeUsed: true, startedAt: 1000))
        XCTAssertEqual(cpMergeAutoResult(before, cpPauseRun(before), step, true),
                       CpRun(armed: false, snoozeUsed: true, startedAt: 1000))
        XCTAssertEqual(cpMergeAutoResult(before, cpPauseRun(before), step, false), cpPauseRun(before))
    }
    // 18
    func testMergeCantResurrectCompletedOrDifferent() {
        let run = CpRun(armed: true, startedAt: 1000)
        XCTAssertEqual(cpMergeAutoResult(run, CpRun(), .snooze(run), true), CpRun())
        let newer = CpRun(armed: true, startedAt: 99)
        XCTAssertEqual(cpMergeAutoResult(run, newer, .snooze(run), true), newer)
    }
    // 19
    func testExhaustedRetryWaitsForManualRecovery() {
        let failed = cpRecordAutoFailure(armed, "ACCEPT_PENDING", 5000, "nope")
        XCTAssertEqual(cpRunFromWire(cpRunToWire(failed)), failed)                      // wire round-trip
        XCTAssertEqual(decide(failed, "ACCEPT_PENDING", 5000, 1, false, 4900), .idle)   // same phase: no retry
        XCTAssertEqual(decide(failed, "ACCEPT_PENDING", 6000, 1, false, 5900), .accept(failed)) // phase changed
        XCTAssertEqual(decide(failed, "CHARGING", nil, 0, true, 5900), .done)
        XCTAssertEqual(cpAfterManual(failed, .accept, true).failedState, "")
        let recovered = cpResumeRun(cpPauseRun(failed), 0, 99)
        XCTAssertEqual(recovered.failedState, "")
        XCTAssertTrue(recovered.snoozeUsed)
    }
    // 20,21,22
    func testArmAndEnd() {
        XCTAssertEqual(cpArmForCommand(CpRun(), .join, autoRun: true, now: 5), CpRun(armed: true, startedAt: 5))
        XCTAssertFalse(cpArmForCommand(CpRun(), .join, autoRun: false, now: 5).armed)
        XCTAssertTrue(cpManualEndsRun(.leave))
        for c: CpCommand in [.accept, .snooze(600), .unsnooze, .start, .stop, .still, .done, .join] {
            XCTAssertFalse(cpManualEndsRun(c), "\(c) should not end the run")
        }
    }
}

private extension CpRun {
    func snoozeUsedCopy() -> CpRun { var x = self; x.snoozeUsed = true; return x }
}
