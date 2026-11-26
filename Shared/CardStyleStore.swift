import Foundation
import HearthKit

/// App-Group store for card styling preferences.
/// Persists a global CardStyle + optional per-kind overrides.
public enum CardStyleStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let globalKey = "cardStyleGlobal"
    private static let overridesKey = "cardStyleOverrides"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Returns the effective style for the given widget kind.
    /// - Parameter kind: The widget kind to query (nil for global-only lookup).
    /// - Returns: Override for the kind if present, else global, else `.default`.
    public static func effectiveStyle(for kind: HomeWidgetKind?) -> CardStyle {
        guard let kind else { return global() }
        return resolveStyle(global: global(), override: override(for: kind))
    }

    /// Returns the global card style.
    public static func global() -> CardStyle {
        guard let data = defaults.data(forKey: globalKey),
              let decoded = try? JSONDecoder().decode(CardStyle.self, from: data) else {
            return .default
        }
        return decoded
    }

    /// Sets the global card style.
    public static func setGlobal(_ style: CardStyle) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        defaults.set(data, forKey: globalKey)
    }

    /// Returns the override style for a specific widget kind, if any.
    public static func override(for kind: HomeWidgetKind) -> CardStyle? {
        guard let data = defaults.data(forKey: overridesKey),
              let overrides = try? JSONDecoder().decode([String: CardStyle].self, from: data) else {
            return nil
        }
        return overrides[kind.rawValue]
    }

    /// Sets an override style for a specific widget kind.
    public static func setOverride(_ style: CardStyle, for kind: HomeWidgetKind) {
        var overrides = loadOverrides()
        overrides[kind.rawValue] = style
        saveOverrides(overrides)
    }

    /// Clears the override style for a specific widget kind.
    public static func clearOverride(for kind: HomeWidgetKind) {
        var overrides = loadOverrides()
        overrides.removeValue(forKey: kind.rawValue)
        saveOverrides(overrides)
    }

    // MARK: - Private Helpers

    private static func loadOverrides() -> [String: CardStyle] {
        guard let data = defaults.data(forKey: overridesKey),
              let overrides = try? JSONDecoder().decode([String: CardStyle].self, from: data) else {
            return [:]
        }
        return overrides
    }

    private static func saveOverrides(_ overrides: [String: CardStyle]) {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: overridesKey)
    }
}
