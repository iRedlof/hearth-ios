import XCTest
@testable import HearthKit

/// Tests for the pure `commuteDay(from:in:)` helper that converts Date to yyyymmdd Int.
/// Critical: must use the passed TimeZone, NOT UTC (off-by-one gotcha).
final class CommuteDayTests: XCTestCase {

    func testKnownDateInPST() {
        // Oct 27, 2026 at 10:00 AM PST
        let pst = TimeZone(identifier: "America/Los_Angeles")!
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 27
        components.hour = 10
        components.minute = 0
        components.timeZone = pst

        let date = Calendar.current.date(from: components)!
        let result = commuteDay(from: date, in: pst)

        XCTAssertEqual(20261027, result, "Oct 27, 2026 in PST should produce 20261027")
    }

    func testKnownDateInEST() {
        // Nov 26, 2026 at 3:00 PM EST
        let est = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 26
        components.hour = 15
        components.minute = 0
        components.timeZone = est

        let date = Calendar.current.date(from: components)!
        let result = commuteDay(from: date, in: est)

        XCTAssertEqual(20261126, result, "Nov 26, 2026 in EST should produce 20261126")
    }

    func testMidnightBoundary() {
        // Test that we respect the passed timezone, not UTC
        // Create a date that is Oct 27 at 11:30 PM in PST
        // but would be Oct 28 in UTC
        let pst = TimeZone(identifier: "America/Los_Angeles")!
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 27
        components.hour = 23
        components.minute = 30
        components.timeZone = pst

        let date = Calendar.current.date(from: components)!

        // Should use PST, not UTC
        let resultPST = commuteDay(from: date, in: pst)
        XCTAssertEqual(20261027, resultPST, "Should be Oct 27 in PST")

        // If we incorrectly used UTC, it would be different
        let utc = TimeZone(identifier: "UTC")!
        let resultUTC = commuteDay(from: date, in: utc)
        XCTAssertNotEqual(resultPST, resultUTC, "UTC and PST should differ for this date near midnight PST")
        XCTAssertEqual(20261028, resultUTC, "Should be Oct 28 in UTC")
    }

    func testNewYearsEve() {
        // Dec 31, 2026 at 11:59 PM in any timezone
        let est = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 31
        components.hour = 23
        components.minute = 59
        components.timeZone = est

        let date = Calendar.current.date(from: components)!
        let result = commuteDay(from: date, in: est)

        XCTAssertEqual(20261231, result, "Dec 31, 2026 should produce 20261231")
    }

    func testLeapDay() {
        // Feb 29, 2024 (leap year)
        let pst = TimeZone(identifier: "America/Los_Angeles")!
        var components = DateComponents()
        components.year = 2024
        components.month = 2
        components.day = 29
        components.hour = 12
        components.timeZone = pst

        let date = Calendar.current.date(from: components)!
        let result = commuteDay(from: date, in: pst)

        XCTAssertEqual(20240229, result, "Feb 29, 2024 (leap day) should produce 20240229")
    }
}
