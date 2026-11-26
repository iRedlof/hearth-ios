import XCTest
@testable import HearthKit

private func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

final class TravelTests: XCTestCase {
    let now = iso("2026-11-26T10:00:00Z")

    func testAllDayEventTomorrowProducesTrip() {
        // All-day event starting tomorrow
        let event = LeaveByEvent(
            title: "Conference",
            startDate: iso("2026-11-27T00:00:00Z"),
            endDate: iso("2026-11-27T23:59:59Z"),
            location: "San Francisco",
            isAllDay: true
        )

        // Calendar in a specific timezone (UTC for deterministic test)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let trips = travelTrips(events: [event], now: now, calendar: calendar)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].title, "Conference")
        XCTAssertEqual(trips[0].startDate, iso("2026-11-27T00:00:00Z"))
        // notifyAt should be 8 PM (20:00) on 2026-11-26 (the day before)
        XCTAssertEqual(trips[0].notifyAt, iso("2026-11-26T20:00:00Z"))
    }

    func testTwentyFiveHourEventProducesTrip() {
        // Event lasting 25 hours starting tomorrow
        let event = LeaveByEvent(
            title: "Long meeting",
            startDate: iso("2026-11-27T09:00:00Z"),
            endDate: iso("2026-11-28T10:00:00Z"), // 25 hours later
            location: "Office",
            isAllDay: false
        )

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let trips = travelTrips(events: [event], now: now, calendar: calendar)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].title, "Long meeting")
        XCTAssertEqual(trips[0].notifyAt, iso("2026-11-26T20:00:00Z"))
    }

    func testTwoHourEventIsNotATrip() {
        // Event lasting 2 hours
        let event = LeaveByEvent(
            title: "Short meeting",
            startDate: iso("2026-11-27T09:00:00Z"),
            endDate: iso("2026-11-27T11:00:00Z"), // 2 hours later
            location: "Office",
            isAllDay: false
        )

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let trips = travelTrips(events: [event], now: now, calendar: calendar)

        XCTAssertEqual(trips.count, 0)
    }

    func testTripEightDaysOutIsExcluded() {
        // Trip starting 8 days from now (beyond 7-day window)
        let event = LeaveByEvent(
            title: "Future conference",
            startDate: iso("2026-12-04T00:00:00Z"), // 8 days from now
            endDate: iso("2026-12-05T00:00:00Z"),
            location: "New York",
            isAllDay: true
        )

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let trips = travelTrips(events: [event], now: now, calendar: calendar)

        XCTAssertEqual(trips.count, 0)
    }

    func testNotifyAtInPastIsExcluded() {
        // Event starting today at 11 AM (notifyAt would be yesterday at 8 PM)
        let event = LeaveByEvent(
            title: "Today's trip",
            startDate: iso("2026-11-26T11:00:00Z"),
            endDate: iso("2026-11-27T11:00:00Z"),
            location: "Airport",
            isAllDay: false
        )

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let trips = travelTrips(events: [event], now: now, calendar: calendar)

        // notifyAt would be 2026-11-25T20:00:00Z, which is before now (2026-11-26T10:00:00Z)
        XCTAssertEqual(trips.count, 0)
    }

    func testEightPMComputedInGivenTimezone() {
        // Event starting tomorrow at noon
        let event = LeaveByEvent(
            title: "Trip",
            startDate: iso("2026-11-27T12:00:00Z"),
            endDate: iso("2026-11-28T12:00:00Z"),
            location: "Hotel",
            isAllDay: false
        )

        // Test with PST (UTC-8)
        var pstCalendar = Calendar.current
        pstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let pstTrips = travelTrips(events: [event], now: now, calendar: pstCalendar)
        XCTAssertEqual(pstTrips.count, 1)

        // Test with EST (UTC-5)
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let estTrips = travelTrips(events: [event], now: now, calendar: estCalendar)
        XCTAssertEqual(estTrips.count, 1)

        // The notifyAt times should differ by 3 hours (PST vs EST)
        let timeDiff = abs(pstTrips[0].notifyAt.timeIntervalSince(estTrips[0].notifyAt))
        XCTAssertEqual(timeDiff, 3 * 3600, accuracy: 1) // 3 hours difference
    }

    func testMultipleTripsAreSortedByStartDate() {
        let event1 = LeaveByEvent(
            title: "Later trip",
            startDate: iso("2026-11-30T00:00:00Z"),
            endDate: iso("2026-12-01T00:00:00Z"),
            location: "Hotel",
            isAllDay: true
        )
        let event2 = LeaveByEvent(
            title: "Earlier trip",
            startDate: iso("2026-11-27T00:00:00Z"),
            endDate: iso("2026-11-28T00:00:00Z"),
            location: "Airport",
            isAllDay: true
        )
        let event3 = LeaveByEvent(
            title: "Middle trip",
            startDate: iso("2026-11-29T00:00:00Z"),
            endDate: iso("2026-11-30T00:00:00Z"),
            location: "Train",
            isAllDay: true
        )

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let trips = travelTrips(events: [event1, event2, event3], now: now, calendar: calendar)

        XCTAssertEqual(trips.count, 3)
        XCTAssertEqual(trips[0].title, "Earlier trip")
        XCTAssertEqual(trips[1].title, "Middle trip")
        XCTAssertEqual(trips[2].title, "Later trip")
    }
}
