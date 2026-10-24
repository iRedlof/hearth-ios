import Foundation
import HearthKit

/// Shares the signed-in `HaConfig` between the app and the widget extension via an App Group.
/// (Falls back to standard defaults if the suite is unavailable, e.g. App Group not provisioned.)
public enum HaConfigStore {
    public static let appGroup = "group.com.rohit.hearth"
    private static let key = "haConfig"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    public static func load() -> HaConfig? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HaConfig.self, from: data)
    }

    public static func save(_ config: HaConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }

    public static func clear() { defaults.removeObject(forKey: key) }
}
