import XCTest
@testable import HearthKit

private func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

final class LeaveByTests: XCTestCase {
    let now = iso("2026-11-26T10:00:00Z")

    func testEventWithLocationAndFutureStartProducesCheck() {
        let event = LeaveByEvent(
            title: "Team meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(checks[0].eventTitle, "Team meeting")
        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:40:00Z"))
        XCTAssertEqual(checks[0].items, [.alarm, .lock, .thermostat])
    }

    func testEventWithoutLocationIsExcluded() {
        let event = LeaveByEvent(
            title: "Video call",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: nil
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks.count, 0)
    }

    func testEventWithEmptyLocationIsExcluded() {
        let event = LeaveByEvent(
            title: "Video call",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: ""
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks.count, 0)
    }

    func testEventAlreadyStartedIsExcluded() {
        let event = LeaveByEvent(
            title: "Past meeting",
            startDate: iso("2026-11-26T09:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks.count, 0)
    }

    func testEventWhoseNotifyAtIsInPastIsExcluded() {
        let event = LeaveByEvent(
            title: "Soon meeting",
            startDate: iso("2026-11-26T10:05:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks.count, 0)
    }

    func testMinutesBeforeTenComputesCorrectOffset() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 10,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:50:00Z"))
    }

    func testMinutesBeforeFifteenComputesCorrectOffset() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 15,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:45:00Z"))
    }

    func testMinutesBeforeTwentyComputesCorrectOffset() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:40:00Z"))
    }

    func testMinutesBeforeThirtyComputesCorrectOffset() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 30,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:30:00Z"))
    }

    func testMinutesBeforeFortyFiveComputesCorrectOffset() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 45,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:15:00Z"))
    }

    func testMinutesBeforeSixtyComputesCorrectOffset() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 60,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )

        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:00:00Z"))
    }

    func testOnlyAlarmConfiguredProducesSingleItem() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: false,
            hasClimate: false
        )

        XCTAssertEqual(checks[0].items, [.alarm])
    }

    func testOnlyLockConfiguredProducesSingleItem() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: false,
            hasLock: true,
            hasClimate: false
        )

        XCTAssertEqual(checks[0].items, [.lock])
    }

    func testOnlyClimateConfiguredProducesSingleItem() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: false,
            hasLock: false,
            hasClimate: true
        )

        XCTAssertEqual(checks[0].items, [.thermostat])
    }

    func testNoConfiguredItemsExcludesEvent() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let checks = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: false,
            hasLock: false,
            hasClimate: false
        )

        XCTAssertEqual(checks.count, 0)
    }

    func testMultipleEventsAreSortedByNotifyAt() {
        let event1 = LeaveByEvent(
            title: "Later meeting",
            startDate: iso("2026-11-26T14:00:00Z"),
            location: "Office"
        )
        let event2 = LeaveByEvent(
            title: "Earlier meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )
        let event3 = LeaveByEvent(
            title: "Middle meeting",
            startDate: iso("2026-11-26T12:30:00Z"),
            location: "Office"
        )

        let checks = leaveByChecks(
            events: [event1, event2, event3],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: false,
            hasClimate: false
        )

        XCTAssertEqual(checks.count, 3)
        XCTAssertEqual(checks[0].eventTitle, "Earlier meeting")
        XCTAssertEqual(checks[0].notifyAt, iso("2026-11-26T10:40:00Z"))
        XCTAssertEqual(checks[1].eventTitle, "Middle meeting")
        XCTAssertEqual(checks[1].notifyAt, iso("2026-11-26T12:10:00Z"))
        XCTAssertEqual(checks[2].eventTitle, "Later meeting")
        XCTAssertEqual(checks[2].notifyAt, iso("2026-11-26T13:40:00Z"))
    }

    func testItemsFollowStableOrder() {
        let event = LeaveByEvent(
            title: "Meeting",
            startDate: iso("2026-11-26T11:00:00Z"),
            location: "Office"
        )

        // Test various combinations to ensure stable order: alarm, lock, thermostat
        let checks1 = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: true
        )
        XCTAssertEqual(checks1[0].items, [.alarm, .lock, .thermostat])

        let checks2 = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: false,
            hasLock: true,
            hasClimate: true
        )
        XCTAssertEqual(checks2[0].items, [.lock, .thermostat])

        let checks3 = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: false,
            hasClimate: true
        )
        XCTAssertEqual(checks3[0].items, [.alarm, .thermostat])

        let checks4 = leaveByChecks(
            events: [event],
            minutesBefore: 20,
            now: now,
            hasAlarm: true,
            hasLock: true,
            hasClimate: false
        )
        XCTAssertEqual(checks4[0].items, [.alarm, .lock])
    }
}
