import Testing
import Foundation
@testable import HearthKit

@Suite("Routines Suggester Tests")
struct RoutinesSuggesterTests {
    // MARK: - Test: Record appends new entry

    @Test("Record appends new entry to history")
    func testRecordAppendsNewEntry() {
        let history: [ActionHistoryRecord] = []
        let entry = ActionHistoryRecord(timestamp: Date(), entityIDs: ["lock.a"])
        let updated = RoutinesSuggester.record(history: history, newEntry: entry)
        #expect(updated.count == 1)
        #expect(updated.first?.entityIDs == ["lock.a"])
    }

    // MARK: - Test: Suggested routines threshold (4 occurrences in 7 days)

    @Test("4 identical action-sets within 7 days suggests 1 routine")
    func testSuggestedRoutinesThresholdFour() {
        let now = Date()
        var history: [ActionHistoryRecord] = []
        // Android uses 4 occurrences in 7 days, not 6 in 14
        for i in 0..<4 {
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 86400))
            history.append(ActionHistoryRecord(timestamp: timestamp, entityIDs: ["lock.a", "alarm.b"]))
        }
        let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.entityIDs.sorted() == ["alarm.b", "lock.a"])
        #expect(suggestions.first?.occurrences.count == 4)
    }

    @Test("3 identical action-sets returns 0 suggestions (below threshold)")
    func testSuggestedRoutinesBelowThreshold() {
        let now = Date()
        var history: [ActionHistoryRecord] = []
        for i in 0..<3 {
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 86400))
            history.append(ActionHistoryRecord(timestamp: timestamp, entityIDs: ["lock.a"]))
        }
        let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
        #expect(suggestions.isEmpty)
    }

    // MARK: - Test: Action-set order normalization (Android sorts for matching)

    @Test("Action-sets are normalized for matching - order doesn't distinguish")
    func testActionSetOrderNormalized() {
        let now = Date()
        var history: [ActionHistoryRecord] = []
        // 2 × [lock.a, alarm.b] + 2 × [alarm.b, lock.a] = 4 occurrences of same set
        for i in 0..<2 {
            history.append(ActionHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: ["lock.a", "alarm.b"]))
        }
        for i in 2..<4 {
            history.append(ActionHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: ["alarm.b", "lock.a"]))
        }
        let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
        // Android normalizes order, so these should match
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.entityIDs.sorted() == ["alarm.b", "lock.a"])
    }

    // MARK: - Test: Matches Goodnight key

    @Test("Routine matching goodnightActionSet has matchesGoodnightKey = true")
    func testMatchesGoodnightKey() {
        let now = Date()
        let goodnightSet = ["cover.garage", "light.kitchen", "lock.front", "alarm_control_panel.panel"]
        var history: [ActionHistoryRecord] = []
        for i in 0..<4 {
            history.append(ActionHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: goodnightSet))
        }
        let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: goodnightSet)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.matchesGoodnightKey == true)
    }

    @Test("Routine NOT matching goodnightActionSet has matchesGoodnightKey = false")
    func testDoesNotMatchGoodnightKey() {
        let now = Date()
        let goodnightSet = ["cover.garage", "light.kitchen", "lock.front", "alarm_control_panel.panel"]
        var history: [ActionHistoryRecord] = []
        for i in 0..<4 {
            history.append(ActionHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: ["lock.a", "alarm.b"]))
        }
        let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: goodnightSet)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.matchesGoodnightKey == false)
    }

    // MARK: - Test: Prune history (28-day window, not 14)

    @Test("Prune history removes entries older than 28 days")
    func testPruneHistoryRemovesOldEntries() {
        let now = Date()
        let old = ActionHistoryRecord(timestamp: now.addingTimeInterval(-29 * 86400), entityIDs: ["lock.a"])
        let recent = ActionHistoryRecord(timestamp: now.addingTimeInterval(-27 * 86400), entityIDs: ["lock.b"])
        let pruned = RoutinesSuggester.pruneHistory([old, recent], now: now)
        #expect(pruned.count == 1)
        #expect(pruned.first?.entityIDs == ["lock.b"])
    }

    @Test("Day-8 rolloff: pattern drops below threshold when window moves")
    func testDay8RolloffDoesNotSuggest() {
        // 4 entries at days -4, -5, -6, -7 from baseDate
        let baseDate = Date()
        var history: [ActionHistoryRecord] = []
        for i in 4...7 {
            history.append(ActionHistoryRecord(timestamp: baseDate.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: ["lock.a"]))
        }

        // At baseDate, we have 4 entries in last 7 days
        let suggestions1 = RoutinesSuggester.suggestedRoutines(from: history, now: baseDate, goodnightActionSet: nil)
        #expect(suggestions1.count == 1)  // 4 in last 7 days meets threshold

        // Advance 2 days: entries at -4,-5,-6,-7 become -6,-7,-8,-9 (day -8 is outside 7-day window)
        let futureDate = baseDate.addingTimeInterval(TimeInterval(2 * 86400))
        let suggestions2 = RoutinesSuggester.suggestedRoutines(from: history, now: futureDate, goodnightActionSet: nil)
        #expect(suggestions2.isEmpty)  // Only 3 remain in window, below threshold of 4
    }

    // MARK: - Test: Day pattern detection

    @Test("Day pattern detects weeknights (Mon-Fri)")
    func testDayPatternWeeknight() {
        let calendar = Calendar.current
        // Find a Monday in the past week
        let now = Date()
        var monday = now
        while calendar.component(.weekday, from: monday) != 2 {  // 2 = Monday
            monday = calendar.date(byAdding: .day, value: -1, to: monday)!
        }

        var history: [ActionHistoryRecord] = []
        // Add 4 entries on consecutive weekdays: Mon, Tue, Wed, Thu
        for i in 0..<4 {
            let timestamp = calendar.date(byAdding: .day, value: i, to: monday)!
            history.append(ActionHistoryRecord(timestamp: timestamp, entityIDs: ["lock.a"]))
        }

        let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.dayPattern == .weeknights)
    }

    // MARK: - Test: History cap at 500 entries (Android uses 500, not 100)

    @Test("History caps at 500 entries")
    func testHistoryCapAt500Entries() {
        var history: [ActionHistoryRecord] = []
        for i in 0..<500 {
            history.append(ActionHistoryRecord(timestamp: Date().addingTimeInterval(TimeInterval(-i * 3600)), entityIDs: ["lock.\(i)"]))
        }
        let capped = RoutinesSuggester.record(history: history, newEntry: ActionHistoryRecord(timestamp: Date(), entityIDs: ["lock.new"]))
        #expect(capped.count <= 500)
    }
}
