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

    /// Whether the morning-commute auto-join feature is enabled.
    public static var enabled: Bool {
        get { defaults.bool(forKey: enabledKey) } // absent → false (UserDefaults default)
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// Whether the check-before-leave reminder feature is enabled.
    public static var checkBeforeLeaveEnabled: Bool {
        get { defaults.bool(forKey: checkBeforeLeaveEnabledKey) } // absent → false (UserDefaults default)
        set { defaults.set(newValue, forKey: checkBeforeLeaveEnabledKey) }
    }

    /// The day stamp (yyyymmdd) of the last `.armAuto` action, for once-per-morning debounce.
    /// Absent key → nil (engine treats as "no action today" — safe).
    public static var lastArmDay: CommuteDay? {
        get {
            guard defaults.object(forKey: lastArmDayKey) != nil else { return nil }
            return defaults.integer(forKey: lastArmDayKey)
        }
        set {
            if let value = newValue {
                defaults.set(value, forKey: lastArmDayKey)
            } else {
                defaults.removeObject(forKey: lastArmDayKey)
            }
        }
    }

    /// The day stamp (yyyymmdd) of the last `.notifySignIn` action, for once-per-morning debounce.
    /// Absent key → nil (engine treats as "no action today" — safe).
    public static var lastNotifyDay: CommuteDay? {
        get {
            guard defaults.object(forKey: lastNotifyDayKey) != nil else { return nil }
            return defaults.integer(forKey: lastNotifyDayKey)
        }
        set {
            if let value = newValue {
                defaults.set(value, forKey: lastNotifyDayKey)
            } else {
                defaults.removeObject(forKey: lastNotifyDayKey)
            }
        }
    }

    /// The timestamp of the last successful sensor fetch, for the detection status row.
    /// Absent key → nil (never heard from sensors).
    public static var lastHeard: Date? {
        get { defaults.object(forKey: lastHeardKey) as? Date }
        set { defaults.set(newValue, forKey: lastHeardKey) }
    }
}
