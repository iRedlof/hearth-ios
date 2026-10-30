import XCTest
@testable import HearthKit

final class AlarmSafetyTests: XCTestCase {
    func testUnconfiguredFetchShowsSetupWithoutSampleSecurityStatus() async {
        let empty = HaConfig(baseUrl: "", token: "", entityId: "")
        let snapshot = await fetchAlarmSnapshot(empty, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(snapshot.stateWord, "Set up")
        XCTAssertEqual(snapshot.checkedAt, "—")
        XCTAssertTrue(snapshot.actions.isEmpty)
        XCTAssertNil(snapshot.doorLocked)
    }

    func testUnknownAlarmCannotExposeSecurityCommands() {
        for state in [nil, "", "unknown", "unavailable", "unexpected"] as [String?] {
            XCTAssertTrue(actionsFor(state).isEmpty, "\(state ?? "nil")")
        }
    }

    func testUnknownLockCannotOfferLockCommand() {
        for state in [nil, "", "unknown", "unavailable", "unexpected"] as [String?] {
            XCTAssertNil(lockActionFor(state), "\(state ?? "nil")")
        }
    }

    func testHistoricalAlarmKeepsItsStateWithoutCommandButtons() {
        let snapshot = alarmSnapshot(alarm: AlarmState(state: "armed_home", lastChanged: nil),
            lockState: nil, lockChanged: nil, name: "Home", error: "Can't reach Home Assistant",
            checkedAt: Date(timeIntervalSince1970: 50), now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(snapshot.stateWord, "Armed home")
        XCTAssertEqual(snapshot.tone, .offline)
        XCTAssertTrue(snapshot.actions.isEmpty)
    }
}
