import Foundation
import HearthKit

/// App-Group store for ChargePoint morning-commute persistence.
/// Stores enabled flag and once-per-morning debounce day stamps (lastArmDay, lastNotifyDay).
public enum CommuteStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let enabledKey = "commute.enabled"
    private static let checkBeforeLeaveEnabledKey = "commute.checkBeforeLeaveEnabled"
    private static let lastArmDayKey = "commute.lastArmDay"
    private static let lastNotifyDayKey = "commute.lastNotifyDay"
    private static let lastHeardKey = "commute.lastHeard"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Whether the morning-commute auto-join feature is enabled (gates armAuto branch).
    public static var enabled: Bool {
        get { enabled(defaults: defaults) }
        set { setEnabled(newValue, defaults: defaults) }
    }

    /// Injectable accessor for testing (absent → false).
    public static func enabled(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// Injectable setter for testing.
    public static func setEnabled(_ value: Bool, defaults: UserDefaults) {
        defaults.set(value, forKey: enabledKey)
    }

    /// Whether the check-before-leave notification feature is enabled (gates notifySignIn branch).
    public static var checkBeforeLeaveEnabled: Bool {
        get { checkBeforeLeaveEnabled(defaults: defaults) }
        set { setCheckBeforeLeaveEnabled(newValue, defaults: defaults) }
    }

    /// Injectable accessor for testing (absent → false).
    public static func checkBeforeLeaveEnabled(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: checkBeforeLeaveEnabledKey)
    }

    /// Injectable setter for testing.
    public static func setCheckBeforeLeaveEnabled(_ value: Bool, defaults: UserDefaults) {
        defaults.set(value, forKey: checkBeforeLeaveEnabledKey)
    }

    /// The day stamp (yyyymmdd) of the last `.armAuto` action, for once-per-morning debounce.
    /// Absent key → nil (engine treats as "no action today" — safe).
    public static var lastArmDay: CommuteDay? {
        get { lastArmDay(defaults: defaults) }
        set { setLastArmDay(newValue, defaults: defaults) }
    }

    /// Injectable accessor for testing (absent → nil).
    public static func lastArmDay(defaults: UserDefaults) -> CommuteDay? {
        guard defaults.object(forKey: lastArmDayKey) != nil else { return nil }
        return defaults.integer(forKey: lastArmDayKey)
    }

    /// Injectable setter for testing.
    public static func setLastArmDay(_ value: CommuteDay?, defaults: UserDefaults) {
        if let value = value {
            defaults.set(value, forKey: lastArmDayKey)
        } else {
            defaults.removeObject(forKey: lastArmDayKey)
        }
    }

    /// The day stamp (yyyymmdd) of the last `.notifySignIn` action, for once-per-morning debounce.
    /// Absent key → nil (engine treats as "no action today" — safe).
    public static var lastNotifyDay: CommuteDay? {
        get { lastNotifyDay(defaults: defaults) }
        set { setLastNotifyDay(newValue, defaults: defaults) }
    }

    /// Injectable accessor for testing (absent → nil).
    public static func lastNotifyDay(defaults: UserDefaults) -> CommuteDay? {
        guard defaults.object(forKey: lastNotifyDayKey) != nil else { return nil }
        return defaults.integer(forKey: lastNotifyDayKey)
    }

    /// Injectable setter for testing.
    public static func setLastNotifyDay(_ value: CommuteDay?, defaults: UserDefaults) {
        if let value = value {
            defaults.set(value, forKey: lastNotifyDayKey)
        } else {
            defaults.removeObject(forKey: lastNotifyDayKey)
        }
    }

    /// The timestamp of the last successful sensor fetch, for the detection status row.
    /// Absent key → nil (never heard from sensors).
    public static var lastHeard: Date? {
        get { defaults.object(forKey: lastHeardKey) as? Date }
        set { defaults.set(newValue, forKey: lastHeardKey) }
    }
}
