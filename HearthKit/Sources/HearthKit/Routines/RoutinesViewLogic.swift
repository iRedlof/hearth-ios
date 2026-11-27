import Foundation

/// Pure view-logic helpers for Routines UI.
/// Extracted for unit testing (Phase 5b lesson: test view logic).
public enum RoutinesViewLogic {

    /// Returns the subtitle for the Routines row in EveryDaySection.
    /// - Parameters:
    ///   - enabled: Whether routines learning is enabled
    ///   - routineCount: Number of learned routines
    /// - Returns: "Off" / "On" / "On · N learned"
    public static func routinesRowSubtitle(enabled: Bool, routineCount: Int) -> String {
        guard enabled else { return "Off" }
        return routineCount == 0 ? "On" : "On · \(routineCount) learned"
    }

    /// Returns the day-pattern subtitle for a routine card matching Android mock copy.
    /// - Parameters:
    ///   - pattern: The day pattern
    ///   - occurrenceCount: Number of occurrences (distinct days)
    /// - Returns: A formatted subtitle string
    public static func dayPatternSubtitle(pattern: RoutineEntry.DayPattern, occurrenceCount: Int) -> String {
        switch pattern {
        case .weeknights:
            return "Weeknights · \(occurrenceCount) of the last 7 weekdays"
        case .weekend:
            return "Weekends · \(occurrenceCount) of the last 7 weekend days"
        case .everyDay:
            return "Every day · \(occurrenceCount) of 14 recent days (the last 7 weekdays and 7 weekend days)"
        case .specific(let days):
            let initials = days.sorted().map { dayInitial(for: $0) }.joined(separator: " ")
            return "\(initials) · \(occurrenceCount) of the last 7"
        }
    }

    /// Returns the active day indices (0=Sun, 1=Mon, ..., 6=Sat) for rendering day pills.
    /// - Parameter pattern: The day pattern
    /// - Returns: Array of active day indices
    public static func activeDayIndices(for pattern: RoutineEntry.DayPattern) -> [Int] {
        switch pattern {
        case .weeknights:
            return [1, 2, 3, 4, 5] // Mon-Fri
        case .weekend:
            return [0, 6] // Sat-Sun
        case .everyDay:
            return [0, 1, 2, 3, 4, 5, 6] // All days
        case .specific(let days):
            return days.sorted()
        }
    }

    // MARK: - Private Helpers

    private static func dayInitial(for dayIndex: Int) -> String {
        switch dayIndex {
        case 0: return "S" // Sunday
        case 1: return "M" // Monday
        case 2: return "T" // Tuesday
        case 3: return "W" // Wednesday
        case 4: return "T" // Thursday
        case 5: return "F" // Friday
        case 6: return "S" // Saturday
        default: return ""
        }
    }
}
