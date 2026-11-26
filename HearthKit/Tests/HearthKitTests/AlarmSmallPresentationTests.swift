import XCTest
@testable import HearthKit

final class AlarmSmallPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func snapshot(_ panel: String?, door: String? = "locked", panelError: String? = nil,
                          doorError: String? = nil) -> AlarmSnapshot {
        alarmSnapshot(alarm: panel.map { AlarmState(state: $0, lastChanged: now.addingTimeInterval(-120)) },
            lockState: door, lockChanged: now.addingTimeInterval(-60), name: "Family Home",
            error: panelError, checkedAt: panel == nil ? nil : now.addingTimeInterval(-30), now: now,
            doorName: "Front Door", doorSelected: true, doorError: doorError,
            doorCheckedAt: door == nil ? nil : now.addingTimeInterval(-20))
    }
    func testAlarmAdvertisesOnlyDesignedSmallAndMedium() {
        XCTAssertEqual(WidgetPreviewKind.alarm.supportedFamilies, [.small, .medium])
    }
    func testFreshTriggerBeatsDoorFailureAndPendingDoor() {
        var snap = snapshot("triggered", doorError: "Signed out: sign in again")
        snap.entityID = "alarm_control_panel.home"; snap.lockID = "lock.front"
        snap = alarmApplyingOperation(snap, AlarmOperation(entityID: snap.lockID, action: "unlock", startedAt: now))
        let content = alarmSmallContent(snap)
        XCTAssertEqual(content.criticalTexts, ["Alarm triggered", "Updating"])
        XCTAssertEqual(content.tone, .triggered)
        XCTAssertTrue(alarmSmallAccessibility(content).contains("unlock"))
    }
    func testDoorWarningRetainsMandatoryPanelRecovery() {
        let cases: [(String?, String?, [String])] = [
            ("armed_home", "Signed out: sign in again", ["Door unlocked", "Last known", "Sign in"]),
            (nil, "Set up the alarm in Settings", ["Door unlocked", "Set up"]),
            (nil, "Can't reach Home Assistant", ["Door unlocked", "No reading"]),
            ("unknown", nil, ["Door unlocked", "Unavailable"])]
        for (panel, error, expected) in cases {
            XCTAssertEqual(alarmSmallContent(snapshot(panel, door: "unlocked", panelError: error)).criticalTexts, expected)
        }
    }
    func testDoorFailuresNeverBecomeFreshWarningsOrSecureAssurance() {
        let content = alarmSmallContent(snapshot("disarmed", door: "unlocked", doorError: "Can't reach Home Assistant"))
        XCTAssertEqual(content.criticalTexts, ["Disarmed"])
        XCTAssertEqual(content.optionalContext, "Door last known")
        XCTAssertEqual(content.tone, .blue)
    }
    func testRetainedTriggerIsHistoryAndRetainedAuthenticationIsExplicit() {
        XCTAssertEqual(alarmSmallContent(snapshot("triggered", panelError: "Can't reach Home Assistant")).criticalTexts, ["Last known"])
        XCTAssertEqual(alarmSmallContent(snapshot("armed_away", panelError: "Signed out: sign in again")).criticalTexts, ["Last known", "Sign in"])
    }
    func testMissingAndUnsupportedReadingsDoNotBorrowSecurity() {
        XCTAssertEqual(alarmSmallContent(snapshot(nil, panelError: "Can't reach Home Assistant")).criticalTexts, ["No reading"])
        for state in ["unknown", "unavailable", "future_state"] {
            XCTAssertEqual(alarmSmallContent(snapshot(state)).criticalTexts, ["Unavailable"])
        }
    }
    func testEveryStableModeAndTransitionRetainsExactMeaning() {
        let states = ["disarmed": "Disarmed", "armed_home": "Armed home", "armed_away": "Armed away",
            "armed_night": "Armed night", "armed_vacation": "Armed vacation", "armed_custom_bypass": "Armed (bypass)",
            "pending": "Entry delay", "arming": "Arming", "disarming": "Disarming"]
        for (state, label) in states { XCTAssertEqual(alarmSmallContent(snapshot(state)).criticalTexts, [label]) }
    }
    func testPendingStablePanelUsesHourglassWithoutChangingObservedState() {
        var snap = snapshot("disarmed"); snap.entityID = "alarm_control_panel.home"
        snap = alarmApplyingOperation(snap, AlarmOperation(entityID: snap.entityID, action: "armAway", startedAt: now))
        let content = alarmSmallContent(snap)
        XCTAssertEqual(content.criticalTexts, ["Disarmed", "Updating"])
        XCTAssertEqual(content.statusSymbol, "hourglass")
    }
    func testOperationFailureNeverRewritesObservedState() {
        var snap = snapshot("disarmed"); snap.entityID = "alarm_control_panel.home"
        snap = alarmApplyingOperation(snap, AlarmOperation(entityID: snap.entityID, action: "armAway", startedAt: now, error: "Rejected"))
        let content = alarmSmallContent(snap)
        XCTAssertEqual(content.criticalTexts, ["Disarmed", "Not confirmed"])
        XCTAssertTrue(alarmSmallAccessibility(content).contains("Rejected"))
    }
    func testRawFactsAndObservationDatesSurviveMapping() {
        let snap = snapshot("disarmed", door: "open")
        XCTAssertEqual(snap.panelRawState, "disarmed"); XCTAssertEqual(snap.doorRawState, "open")
        XCTAssertEqual(snap.panelObservedAt, now.addingTimeInterval(-30))
        XCTAssertEqual(snap.doorObservedAt, now.addingTimeInterval(-20))
        XCTAssertTrue(alarmSmallAccessibility(alarmSmallContent(snap)).contains("Front Door"))
    }
}
