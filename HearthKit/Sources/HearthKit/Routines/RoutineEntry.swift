import Foundation

/// A learned routine: a pattern of actions done repeatedly at similar times on similar days.
public struct RoutineEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let medianTime: Date
    public let entityIDs: [String]  // Canonical ordered entity IDs
    public let occurrences: [Date]  // All matching timestamps within window
    public let dayPattern: DayPattern
    public let matchesGoodnightKey: Bool

    public enum DayPattern: Sendable, Equatable {
        case weeknights  // Mon-Fri
        case everyDay
        case specific([Int])  // 0=Sun, 1=Mon, ..., 6=Sat
    }

    public init(
        id: String,
        medianTime: Date,
        entityIDs: [String],
        occurrences: [Date],
        dayPattern: DayPattern,
        matchesGoodnightKey: Bool
    ) {
        self.id = id
        self.medianTime = medianTime
        self.entityIDs = entityIDs
        self.occurrences = occurrences
        self.dayPattern = dayPattern
        self.matchesGoodnightKey = matchesGoodnightKey
    }
}
