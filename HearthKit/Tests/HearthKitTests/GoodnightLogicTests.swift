import Testing
import Foundation
@testable import HearthKit

@Suite("Goodnight Logic")
struct GoodnightLogicTests {

    // MARK: - Overnight Wrap (21..5)

    @Test("Overnight wrap 21..5: active at 21:00")
    func overnightWrapActiveAt21() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 21, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == true)
    }

    @Test("Overnight wrap 21..5: active at 23:00")
    func overnightWrapActiveAt23() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 23, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == true)
    }

    @Test("Overnight wrap 21..5: active at 00:00")
    func overnightWrapActiveAt00() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 0, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == true)
    }

    @Test("Overnight wrap 21..5: active at 02:00")
    func overnightWrapActiveAt02() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 2, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == true)
    }

    @Test("Overnight wrap 21..5: active at 04:59")
    func overnightWrapActiveAt0459() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 4, minute: 59, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == true)
    }

    @Test("Overnight wrap 21..5: inactive at 05:00 (endHour boundary)")
    func overnightWrapInactiveAt05() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 5, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == false)
    }

    @Test("Overnight wrap 21..5: inactive at 12:00")
    func overnightWrapInactiveAt12() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 12, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == false)
    }

    @Test("Overnight wrap 21..5: inactive at 20:59 (before startHour)")
    func overnightWrapInactiveAt2059() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 20, minute: 59, in: calendar)
        #expect(goodnightActive(now: now, startHour: 21, endHour: 5, calendar: calendar) == false)
    }

    // MARK: - Non-Wrap Window (1..5)

    @Test("Non-wrap 1..5: active at 01:00")
    func nonWrapActiveAt01() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 1, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 1, endHour: 5, calendar: calendar) == true)
    }

    @Test("Non-wrap 1..5: active at 04:00")
    func nonWrapActiveAt04() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 4, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 1, endHour: 5, calendar: calendar) == true)
    }

    @Test("Non-wrap 1..5: inactive at 00:00")
    func nonWrapInactiveAt00() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 0, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 1, endHour: 5, calendar: calendar) == false)
    }

    @Test("Non-wrap 1..5: inactive at 05:00 (endHour boundary)")
    func nonWrapInactiveAt05() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 5, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 1, endHour: 5, calendar: calendar) == false)
    }

    @Test("Non-wrap 1..5: inactive at 12:00")
    func nonWrapInactiveAt12() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = makeDate(hour: 12, minute: 0, in: calendar)
        #expect(goodnightActive(now: now, startHour: 1, endHour: 5, calendar: calendar) == false)
    }

    // MARK: - Empty Window (startHour == endHour)

    @Test("Empty window (5..5): inactive at any hour")
    func emptyWindowAlwaysInactive() {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let tests = [0, 5, 12, 23]
        for hour in tests {
            let now = makeDate(hour: hour, minute: 0, in: calendar)
            #expect(goodnightActive(now: now, startHour: 5, endHour: 5, calendar: calendar) == false,
                   "Hour \(hour) should be inactive when startHour == endHour")
        }
    }

    // MARK: - Timezone Honored

    @Test("Timezone honored: same absolute Date, different local hours")
    func timezoneHonored() {
        // Create a fixed UTC date at 02:00 UTC
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 26
        components.hour = 2
        components.minute = 0
        let utcCalendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let absoluteDate = utcCalendar.date(from: components)!

        // In UTC (02:00), window 21..5 should be ACTIVE
        let utcResult = goodnightActive(now: absoluteDate, startHour: 21, endHour: 5, calendar: utcCalendar)
        #expect(utcResult == true, "02:00 UTC should be active in 21..5 window")

        // In PST (UTC-8), the same absolute moment is 18:00 PST (previous day)
        // Window 21..5 should be INACTIVE at 18:00
        let pstCalendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: -8 * 3600)!)
        let pstResult = goodnightActive(now: absoluteDate, startHour: 21, endHour: 5, calendar: pstCalendar)
        #expect(pstResult == false, "18:00 PST (same absolute moment as 02:00 UTC) should be inactive in 21..5 window")

        // Verify they differ
        #expect(utcResult != pstResult, "Same absolute Date must yield different active results in different timezones")
    }

    // MARK: - Arm Mode Resolution

    @Test("resolveArmMode: night + unsupported panel → home")
    func armModeNightUnsupportedFallsBackToHome() {
        let result = resolveArmMode(preferred: .night, panelSupportsNight: false)
        #expect(result == .home)
    }

    @Test("resolveArmMode: night + supported panel → night")
    func armModeNightSupportedStaysNight() {
        let result = resolveArmMode(preferred: .night, panelSupportsNight: true)
        #expect(result == .night)
    }

    @Test("resolveArmMode: home + unsupported panel → home")
    func armModeHomeUnsupportedStaysHome() {
        let result = resolveArmMode(preferred: .home, panelSupportsNight: false)
        #expect(result == .home)
    }

    @Test("resolveArmMode: home + supported panel → home")
    func armModeHomeSupportedStaysHome() {
        let result = resolveArmMode(preferred: .home, panelSupportsNight: true)
        #expect(result == .home)
    }

    // MARK: - Lights To Turn Off

    @Test("lightsToTurnOff: excludes keep-on lights")
    func lightsExcludesKeepOn() {
        let all = ["light.living_room", "light.bedroom", "light.kitchen"]
        let keepOn = ["light.bedroom"]
        let result = lightsToTurnOff(all: all, keepOn: keepOn)
        #expect(result == ["light.living_room", "light.kitchen"])
    }

    @Test("lightsToTurnOff: empty keepOn returns all lights (deduplicated)")
    func lightsEmptyKeepOnReturnsAll() {
        let all = ["light.living_room", "light.bedroom", "light.living_room"]
        let keepOn: [String] = []
        let result = lightsToTurnOff(all: all, keepOn: keepOn)
        #expect(result == ["light.living_room", "light.bedroom"])
    }

    @Test("lightsToTurnOff: keepOn id not in all has no effect")
    func lightsKeepOnNotInAllHasNoEffect() {
        let all = ["light.living_room", "light.bedroom"]
        let keepOn = ["light.kitchen"]
        let result = lightsToTurnOff(all: all, keepOn: keepOn)
        #expect(result == ["light.living_room", "light.bedroom"])
    }

    @Test("lightsToTurnOff: duplicates in all are deduplicated")
    func lightsDuplicatesDeduped() {
        let all = ["light.a", "light.b", "light.a", "light.c", "light.b"]
        let keepOn = ["light.c"]
        let result = lightsToTurnOff(all: all, keepOn: keepOn)
        #expect(result == ["light.a", "light.b"])
    }

    @Test("lightsToTurnOff: empty all returns empty")
    func lightsEmptyAllReturnsEmpty() {
        let all: [String] = []
        let keepOn = ["light.bedroom"]
        let result = lightsToTurnOff(all: all, keepOn: keepOn)
        #expect(result == [])
    }

    // MARK: - Helpers

    private func makeCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func makeDate(hour: Int, minute: Int, in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 26
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
