import XCTest
@testable import HearthKit

/// The nearest iOS equivalent of Android's exact alarm (`CpAutoStep.WakeAt`): the moment the widget
/// asks WidgetKit, and the app asks the system, to run ChargePoint again.
final class CpNextReloadTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var nowMs: Int64 { Int64(now.timeIntervalSince1970 * 1000) }
    private let armed = CpRun(armed: true, startedAt: 1000)

    private func next(_ run: CpRun, _ phase: String, deadlineIn seconds: Int64?, snoozes: Int? = nil,
                      charging: Bool = false) -> TimeInterval {
        cpNextReload(run: run, phase: phase, deadlineMs: seconds.map { nowMs + $0 * 1000 },
                     snoozesLeft: snoozes, charging: charging, now: now).timeIntervalSince(now)
    }

    func testNotArmedAndNothingPendingUsesTheIdleInterval() {
        XCTAssertEqual(next(CpRun(), "NOT_QUEUED", deadlineIn: nil), CP_RELOAD_IDLE_SECONDS)
    }

    /// Tonight's real case: offer open for 20 min, Auto armed, a flat 15-minute refresh would land
    /// at minute 15 (too early: the window opens at minute 18) and minute 30 (too late).
    func testArmedOfferChecksInThenWakesAtTheStartOfTheActionWindow() {
        // 20 minutes left: the window opens in 18. Check in at the armed interval first…
        XCTAssertEqual(next(armed, "ACCEPT_PENDING", deadlineIn: 1200), CP_RELOAD_ARMED_SECONDS)
        // …and once the window is nearer than that, wake exactly as it opens (deadline − 2 min).
        XCTAssertEqual(next(armed, "ACCEPT_PENDING", deadlineIn: 320), 320 - 120 + CP_WAKE_SLACK_SECONDS, accuracy: 0.001)
    }

    /// Walking the real case forward: every wake lands before the window closes, and one lands in it.
    func testATwentyMinuteOfferAlwaysGetsAWakeInsideItsWindow() throws {
        var left: TimeInterval = 1200; var wakes: [TimeInterval] = []
        while left > 120 {
            let wait = next(armed, "ACCEPT_PENDING", deadlineIn: Int64(left))
            left -= wait; wakes.append(left)
        }
        XCTAssertLessThanOrEqual(wakes.count, 5, "no more than a handful of refreshes")
        XCTAssertGreaterThan(try XCTUnwrap(wakes.last), 60, "the last wake is inside the window with time to act")
        XCTAssertLessThanOrEqual(try XCTUnwrap(wakes.last), 120)
    }

    func testArmedOfferFarAwayStillChecksInAtTheArmedInterval() {
        // A 60-minute hold: look in every few minutes, do not sleep until the window.
        XCTAssertEqual(next(armed, "ACCEPT_PENDING", deadlineIn: 3600), CP_RELOAD_ARMED_SECONDS)
    }

    func testArmedAndAlreadyInsideTheWindowComesBackSoon() {
        // The step was due on this run (it may have failed or still be in flight): look again shortly.
        XCTAssertEqual(next(armed, "ACCEPT_PENDING", deadlineIn: 60), CP_RELOAD_AFTER_ACTION_SECONDS)
    }

    func testArmedHeldChargerWakesForTheSnooze() {
        let wake = next(armed, "PENDING_PLUG_IN", deadlineIn: 300, snoozes: 1)
        XCTAssertEqual(wake, 300 - 120 + CP_WAKE_SLACK_SECONDS, accuracy: 0.001)
    }

    func testArmedAndWaitingForAnOfferChecksInAtTheArmedInterval() {
        XCTAssertEqual(next(armed, "WAITING", deadlineIn: nil), CP_RELOAD_ARMED_SECONDS)
        XCTAssertEqual(next(armed, "PASS", deadlineIn: nil), CP_RELOAD_ARMED_SECONDS)
    }

    func testNotArmedOfferRefreshesWhenItEnds() {
        // Nobody will act for the person, but the card must stop saying "your turn" when it is over.
        XCTAssertEqual(next(CpRun(), "ACCEPT_PENDING", deadlineIn: 300), 300 + CP_WAKE_SLACK_SECONDS, accuracy: 0.001)
        XCTAssertEqual(next(CpRun(), "ACCEPT_PENDING", deadlineIn: 3600), CP_RELOAD_IDLE_SECONDS)
    }

    func testChargingUsesTheIdleInterval() {
        XCTAssertEqual(next(armed, "CHARGING", deadlineIn: nil, charging: true), CP_RELOAD_IDLE_SECONDS)
    }

    func testNeverInThePast() {
        XCTAssertGreaterThan(next(CpRun(), "ACCEPT_PENDING", deadlineIn: -30), 0)
        XCTAssertGreaterThan(next(armed, "ACCEPT_PENDING", deadlineIn: -30), 0)
    }
}
