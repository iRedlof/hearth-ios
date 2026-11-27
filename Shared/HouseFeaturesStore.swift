import Foundation
import HearthKit

/// App-Group store for house features (leave-by, travel, safety) persistence.
public enum HouseFeaturesStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let leaveByEnabledKey = "houseFeatures.leaveByEnabled"
    private static let leaveByMinutesKey = "houseFeatures.leaveByMinutes"
    private static let travelEnabledKey = "houseFeatures.travelEnabled"
    private static let safetyEnabledKey = "houseFeatures.safetyEnabled"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: - Leave-by

    /// Whether the leave-by feature is enabled
    public static var leaveByEnabled: Bool {
        get { defaults.bool(forKey: leaveByEnabledKey) } // absent → false
        set { defaults.set(newValue, forKey: leaveByEnabledKey) }
    }

    /// Minutes before event to notify (default: 20)
    public static var leaveByMinutes: Int {
        get {
            let stored = defaults.integer(forKey: leaveByMinutesKey)
            return stored > 0 ? stored : 20 // absent or 0 → default 20
        }
        set { defaults.set(newValue, forKey: leaveByMinutesKey) }
    }

    // MARK: - Travel

    /// Whether the travel-days feature is enabled
    public static var travelEnabled: Bool {
        get { defaults.bool(forKey: travelEnabledKey) } // absent → false
        set { defaults.set(newValue, forKey: travelEnabledKey) }
    }

    // MARK: - Safety

    /// Whether the safety-alerts feature is enabled
    public static var safetyEnabled: Bool {
        get { defaults.bool(forKey: safetyEnabledKey) } // absent → false
        set { defaults.set(newValue, forKey: safetyEnabledKey) }
    }

    // MARK: - Routines

    private static let routinesEnabledKey = "houseFeatures.routinesEnabled"

    /// Whether the routines feature is enabled
    public static var routinesEnabled: Bool {
        get { routinesEnabled(defaults: nil) }
        set { setRoutinesEnabled(newValue, defaults: nil) }
    }

    /// Injectable getter for testing. Returns false if the key is absent.
    public static func routinesEnabled(defaults: UserDefaults?) -> Bool {
        let store = defaults ?? self.defaults
        return store.bool(forKey: routinesEnabledKey) // absent → false
    }

    /// Injectable setter for testing.
    public static func setRoutinesEnabled(_ value: Bool, defaults: UserDefaults?) {
        let store = defaults ?? self.defaults
        store.set(value, forKey: routinesEnabledKey)
    }
}
