import Foundation

/// Pure suggester logic for Routines: recording, counting, pattern detection, and suggestion matching.
/// All functions are static and stateless. Android constants (Routines.kt:17-28):
/// - Threshold: 4 occurrences (ROUTINE_MIN_DAYS)
/// - Window: 7 days lookback (ROUTINE_LOOKBACK_DAYS)
/// - Retention: 28 days (ROUTINE_RETAIN_DAYS)
/// - Tolerance: ±45 minutes (ROUTINE_WINDOW_MIN)
/// - Max events: 500 (ROUTINE_MAX_EVENTS)
public enum RoutinesSuggester {
    // Android constants
    private static let retainDays = 28
    private static let maxEvents = 500
    private static let lookbackDays = 7
    private static let minOccurrences = 4
    private static let windowMinutes = 45

    /// Records a new action-set execution, appends it to history, prunes old entries, and caps at 500.
    public static func record(history: [ActionHistoryRecord], newEntry: ActionHistoryRecord) -> [ActionHistoryRecord] {
        let updated = history + [newEntry]
        let sorted = updated.sorted { $0.timestamp < $1.timestamp }
        return Array(sorted.suffix(maxEvents))
    }

    /// Returns suggested routines based on frequency analysis of the last 7 days (Android's ROUTINE_LOOKBACK_DAYS).
    /// A routine is suggested when the same action-set (normalized/sorted) appears ≥4 times in the last 7 days
    /// within ±45 minutes of a median time-of-day.
    public static func suggestedRoutines(
        from history: [ActionHistoryRecord],
        now: Date,
        goodnightActionSet: [String]?
    ) -> [RoutineEntry] {
        let calendar = Calendar.current
        let prunedHistory = pruneHistory(history, now: now)

        // Filter to last 7 days
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let recentHistory = prunedHistory.filter { $0.timestamp >= sevenDaysAgo }

        // Group by normalized action-set (sorted entity IDs)
        let grouped = Dictionary(grouping: recentHistory) { record in
            record.entityIDs.sorted().joined(separator: "|")
        }

        var suggestions: [RoutineEntry] = []
        for (signature, records) in grouped {
            // Check threshold: need at least 4 occurrences
            guard records.count >= minOccurrences else { continue }

            // Extract time-of-day for each occurrence (minutes since midnight)
            let timesByDate = records.map { record -> (date: Date, minutes: Int) in
                let components = calendar.dateComponents([.hour, .minute], from: record.timestamp)
                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                return (record.timestamp, minutes)
            }

            // Calculate median time-of-day
            let sortedTimes = timesByDate.map { $0.minutes }.sorted()
            let medianMinutes = sortedTimes[sortedTimes.count / 2]

            // Cluster occurrences within ±45 minutes of median
            let clustered = timesByDate.filter { (_, minutes) in
                abs(minutes - medianMinutes) <= windowMinutes
            }

            guard clustered.count >= minOccurrences else { continue }

            // Build median time Date by setting now's date with median time
            let medianTime = calendar.date(
                bySettingHour: medianMinutes / 60,
                minute: medianMinutes % 60,
                second: 0,
                of: now
            ) ?? now

            // Detect day pattern
            let occurrenceDates = clustered.map { $0.date }
            let dayPattern = detectDayPattern(dates: occurrenceDates, calendar: calendar)

            // Check if matches Goodnight key (compare sorted arrays)
            let entityIDs = records.first!.entityIDs.sorted()
            let matchesGoodnight: Bool
            if let goodnightSet = goodnightActionSet {
                matchesGoodnight = entityIDs == goodnightSet.sorted()
            } else {
                matchesGoodnight = false
            }

            let entry = RoutineEntry(
                id: signature,
                medianTime: medianTime,
                entityIDs: entityIDs,
                occurrences: occurrenceDates.sorted(),
                dayPattern: dayPattern,
                matchesGoodnightKey: matchesGoodnight
            )
            suggestions.append(entry)
        }

        return suggestions.sorted { $0.medianTime < $1.medianTime }
    }

    /// Prunes history to retain only entries within the last 28 days.
    public static func pruneHistory(_ history: [ActionHistoryRecord], now: Date) -> [ActionHistoryRecord] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -retainDays, to: now) ?? now
        return history.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Private Helpers

    private static func detectDayPattern(dates: [Date], calendar: Calendar) -> RoutineEntry.DayPattern {
        let weekdays = dates.map { calendar.component(.weekday, from: $0) }
        let uniqueDays = Set(weekdays)

        // Weeknights: Mon-Fri (weekday 2-6), ALL must be weeknights
        let weeknightDays = Set([2, 3, 4, 5, 6])
        let isAllWeeknights = uniqueDays.isSubset(of: weeknightDays) && !uniqueDays.isEmpty

        // Weekend: Sat-Sun (weekday 1, 7), ALL must be weekend
        let weekendDays = Set([1, 7])
        let isAllWeekend = uniqueDays.isSubset(of: weekendDays) && !uniqueDays.isEmpty

        if isAllWeeknights {
            return .weeknights
        }

        // Every day: has BOTH weekend and weekday occurrences
        let hasWeekday = uniqueDays.contains(where: { (2...6).contains($0) })
        let hasWeekend = uniqueDays.contains(where: { [1, 7].contains($0) })
        if hasWeekday && hasWeekend {
            return .everyDay
        }

        // Specific days (convert to 0-indexed: 0=Sun, 1=Mon, ..., 6=Sat)
        let zeroBased = uniqueDays.map { ($0 == 1) ? 0 : $0 - 1 }.sorted()
        return .specific(zeroBased)
    }
}
