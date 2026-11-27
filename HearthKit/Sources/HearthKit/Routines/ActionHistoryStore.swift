import Foundation

/// App-Group store for Routines action history persistence.
/// Mirroring GoodnightStore pattern: injectable defaults for testing, absent/corrupt → safe default.
public enum ActionHistoryStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let historyKey = "routines.history"

    private static var defaultDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Loads the action history from UserDefaults.
    /// Returns an empty array if the key is absent or the stored JSON is corrupt.
    ///
    /// - Parameter defaults: Optional UserDefaults instance for testing. Defaults to app-group suite.
    public static func load(defaults: UserDefaults? = nil) -> [ActionHistoryRecord] {
        let store = defaults ?? defaultDefaults
        guard let data = store.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([ActionHistoryRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Saves the action history to UserDefaults.
    /// Silently fails if encoding fails (should never happen with Codable model).
    ///
    /// - Parameters:
    ///   - history: The action history to save.
    ///   - defaults: Optional UserDefaults instance for testing. Defaults to app-group suite.
    public static func save(_ history: [ActionHistoryRecord], defaults: UserDefaults? = nil) {
        let store = defaults ?? defaultDefaults
        guard let data = try? JSONEncoder().encode(history) else { return }
        store.set(data, forKey: historyKey)
    }

    /// Records a new action execution: loads current history, appends the entry, prunes old entries, and saves.
    /// This is the runtime hook path: one-call recording that maintains the 28-day retention window.
    ///
    /// - Parameters:
    ///   - entry: The action history record to append.
    ///   - now: The current time for pruning (injected for testability).
    ///   - defaults: Optional UserDefaults instance for testing. Defaults to app-group suite.
    public static func record(_ entry: ActionHistoryRecord, now: Date, defaults: UserDefaults? = nil) {
        // Capture values before async boundary (Sendable compliance)
        let currentHistory = load(defaults: defaults)
        let updatedHistory = RoutinesSuggester.record(history: currentHistory, newEntry: entry)
        let prunedHistory = RoutinesSuggester.pruneHistory(updatedHistory, now: now)
        save(prunedHistory, defaults: defaults)
    }
}
