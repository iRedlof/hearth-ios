import Foundation
import HearthKit

/// Shares the signed-in `HaConfig` between the app and the widget extension via an App Group.
/// (Falls back to standard defaults if the suite is unavailable, e.g. App Group not provisioned.)
public enum HaConfigStore {
    public static let appGroup = "group.com.rohit.hearth"
    private static let key = "haConfig"
    private static let scopeKey = "haRequestScope"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    public static func load() -> HaConfig? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HaConfig.self, from: data)
    }

    public static func save(_ config: HaConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        if !haSameConnection(load(), config) { invalidateRequests() }
        defaults.set(data, forKey: key)
    }

    /// Stable across entity-picker edits, replaced when signing out or changing server/account.
    public static func requestScope() -> String { defaults.string(forKey: scopeKey) ?? "initial" }
    public static func isCurrent(_ scope: String, config: HaConfig?) -> Bool {
        requestScope() == scope && haSameConnection(load(), config)
    }
    private static func invalidateRequests() {
        defaults.set(UUID().uuidString, forKey: scopeKey)
        CarLiveSnapshot.clear()
    }
    public static func clear() {
        invalidateRequests()
        defaults.removeObject(forKey: key)
    }
}
