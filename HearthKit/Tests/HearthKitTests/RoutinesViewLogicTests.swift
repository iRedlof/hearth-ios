import Testing
import Foundation
@testable import HearthKit

@Suite("RoutinesViewLogic — Subtitle Formatting")
struct RoutinesViewLogicTests {

    @Test("routinesRowSubtitle returns Off when disabled")
    func routinesRowSubtitleDisabled() {
        let subtitle = RoutinesViewLogic.routinesRowSubtitle(enabled: false, routineCount: 0)
        #expect(subtitle == "Off")

        let subtitleWithRoutines = RoutinesViewLogic.routinesRowSubtitle(enabled: false, routineCount: 3)
        #expect(subtitleWithRoutines == "Off")
    }

    @Test("routinesRowSubtitle returns On when enabled with no routines")
    func routinesRowSubtitleEnabledNoRoutines() {
        let subtitle = RoutinesViewLogic.routinesRowSubtitle(enabled: true, routineCount: 0)
        #expect(subtitle == "On")
    }

    @Test("routinesRowSubtitle returns On · N learned when enabled with routines")
    func routinesRowSubtitleEnabledWithRoutines() {
        let subtitle1 = RoutinesViewLogic.routinesRowSubtitle(enabled: true, routineCount: 1)
        #expect(subtitle1 == "On · 1 learned")

        let subtitle3 = RoutinesViewLogic.routinesRowSubtitle(enabled: true, routineCount: 3)
        #expect(subtitle3 == "On · 3 learned")
    }

    @Test("dayPatternSubtitle formats weeknights pattern")
    func dayPatternSubtitleWeeknights() {
        let subtitle = RoutinesViewLogic.dayPatternSubtitle(pattern: .weeknights, occurrenceCount: 6)
        #expect(subtitle == "Weeknights · 6 of the last 7 weekdays")
    }

    @Test("dayPatternSubtitle formats weekend pattern")
    func dayPatternSubtitleWeekend() {
        let subtitle = RoutinesViewLogic.dayPatternSubtitle(pattern: .weekend, occurrenceCount: 4)
        #expect(subtitle == "Weekends · 4 of the last 7 weekend days")
    }

    @Test("dayPatternSubtitle formats every day pattern")
    func dayPatternSubtitleEveryDay() {
        let subtitle = RoutinesViewLogic.dayPatternSubtitle(pattern: .everyDay, occurrenceCount: 11)
        #expect(subtitle == "Every day · 11 of 14 recent days (the last 7 weekdays and 7 weekend days)")
    }

    @Test("dayPatternSubtitle formats specific days pattern")
    func dayPatternSubtitleSpecific() {
        // Monday, Wednesday, Friday
        let subtitle = RoutinesViewLogic.dayPatternSubtitle(pattern: .specific([1, 3, 5]), occurrenceCount: 4)
        #expect(subtitle == "M W F · 4 of the last 7")
    }

    @Test("activeDayIndices returns weekdays for weeknights")
    func activeDayIndicesWeeknights() {
        let indices = RoutinesViewLogic.activeDayIndices(for: .weeknights)
        #expect(indices == [1, 2, 3, 4, 5])
    }

    @Test("activeDayIndices returns weekend days for weekend")
    func activeDayIndicesWeekend() {
        let indices = RoutinesViewLogic.activeDayIndices(for: .weekend)
        #expect(indices == [0, 6])
    }

    @Test("activeDayIndices returns all days for every day")
    func activeDayIndicesEveryDay() {
        let indices = RoutinesViewLogic.activeDayIndices(for: .everyDay)
        #expect(indices == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test("activeDayIndices returns specific days sorted")
    func activeDayIndicesSpecific() {
        let indices = RoutinesViewLogic.activeDayIndices(for: .specific([5, 1, 3]))
        #expect(indices == [1, 3, 5])
    }
}
