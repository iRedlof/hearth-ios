import XCTest
@testable import HearthKit

private func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

final class HouseNotifyTests: XCTestCase {
    func testLeaveByChecksProducePlannedNotifications() {
        let checks = [
            LeaveByCheck(
                eventTitle: "Doctor Appointment",
                notifyAt: iso("2026-11-26T09:30:00Z"),
                items: [.alarm, .lock]
            ),
            LeaveByCheck(
                eventTitle: "Flight to Paris",
                notifyAt: iso("2026-11-27T05:00:00Z"),
                items: [.alarm, .lock, .thermostat]
            ),
        ]

        let planned = plannedNotifications(leaveBy: checks, travel: [])

        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(planned[0].id, "leaveby-doctor-appointment")
        XCTAssertEqual(planned[0].title, "Before leaving for Doctor Appointment")
        XCTAssertEqual(planned[0].body, "Check: alarm, locks")
        XCTAssertEqual(planned[0].fireAt, iso("2026-11-26T09:30:00Z"))

        XCTAssertEqual(planned[1].id, "leaveby-flight-to-paris")
        XCTAssertEqual(planned[1].title, "Before leaving for Flight to Paris")
        XCTAssertEqual(planned[1].body, "Check: alarm, locks, thermostat")
        XCTAssertEqual(planned[1].fireAt, iso("2026-11-27T05:00:00Z"))
    }

    func testTravelTripsProducePlannedNotifications() {
        let trips = [
            Trip(
                title: "Hawaii Vacation",
                startDate: iso("2026-11-30T00:00:00Z"),
                notifyAt: iso("2026-11-29T20:00:00Z")
            ),
            Trip(
                title: "Tokyo Trip",
                startDate: iso("2026-12-05T00:00:00Z"),
                notifyAt: iso("2026-12-04T20:00:00Z")
            ),
        ]

        let planned = plannedNotifications(leaveBy: [], travel: trips)

        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(planned[0].id, "travel-hawaii-vacation")
        XCTAssertEqual(planned[0].title, "Trip tomorrow: Hawaii Vacation")
        XCTAssertEqual(planned[0].body, "Enable vacation mode?")
        XCTAssertEqual(planned[0].fireAt, iso("2026-11-29T20:00:00Z"))

        XCTAssertEqual(planned[1].id, "travel-tokyo-trip")
        XCTAssertEqual(planned[1].title, "Trip tomorrow: Tokyo Trip")
        XCTAssertEqual(planned[1].body, "Enable vacation mode?")
        XCTAssertEqual(planned[1].fireAt, iso("2026-12-04T20:00:00Z"))
    }

    func testMixedLeaveByAndTravelSortedByFireAt() {
        let checks = [
            LeaveByCheck(
                eventTitle: "Meeting",
                notifyAt: iso("2026-11-26T14:00:00Z"),
                items: [.lock]
            ),
        ]
        let trips = [
            Trip(
                title: "Weekend Trip",
                startDate: iso("2026-11-28T00:00:00Z"),
                notifyAt: iso("2026-11-27T20:00:00Z")
            ),
        ]

        let planned = plannedNotifications(leaveBy: checks, travel: trips)

        XCTAssertEqual(planned.count, 2)
        // Earlier fireAt comes first
        XCTAssertEqual(planned[0].id, "leaveby-meeting")
        XCTAssertEqual(planned[0].fireAt, iso("2026-11-26T14:00:00Z"))
        XCTAssertEqual(planned[1].id, "travel-weekend-trip")
        XCTAssertEqual(planned[1].fireAt, iso("2026-11-27T20:00:00Z"))
    }

    func testDuplicateEventTitlesDeduplicatedById() {
        let checks = [
            LeaveByCheck(
                eventTitle: "Meeting",
                notifyAt: iso("2026-11-26T10:00:00Z"),
                items: [.alarm]
            ),
            LeaveByCheck(
                eventTitle: "Meeting", // Same title → same id
                notifyAt: iso("2026-11-26T15:00:00Z"),
                items: [.lock]
            ),
        ]

        let planned = plannedNotifications(leaveBy: checks, travel: [])

        // Only the first "Meeting" check should be included
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned[0].id, "leaveby-meeting")
        XCTAssertEqual(planned[0].fireAt, iso("2026-11-26T10:00:00Z"))
    }

    func testSlugStability() {
        let checks = [
            LeaveByCheck(
                eventTitle: "Doctor Appointment",
                notifyAt: iso("2026-11-26T10:00:00Z"),
                items: [.alarm]
            ),
        ]

        let planned1 = plannedNotifications(leaveBy: checks, travel: [])
        let planned2 = plannedNotifications(leaveBy: checks, travel: [])

        // Same input → same id
        XCTAssertEqual(planned1[0].id, planned2[0].id)
        XCTAssertEqual(planned1[0].id, "leaveby-doctor-appointment")
    }

    func testSlugHandlesSpecialCharacters() {
        let checks = [
            LeaveByCheck(
                eventTitle: "Meeting @ Café #1",
                notifyAt: iso("2026-11-26T10:00:00Z"),
                items: [.alarm]
            ),
        ]

        let planned = plannedNotifications(leaveBy: checks, travel: [])

        // Special characters stripped, spaces → dashes, lowercase
        XCTAssertEqual(planned[0].id, "leaveby-meeting--caf-1")
    }

    func testEmptyInputProducesEmptyOutput() {
        let planned = plannedNotifications(leaveBy: [], travel: [])
        XCTAssertEqual(planned.count, 0)
    }
}
