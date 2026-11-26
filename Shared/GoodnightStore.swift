import Foundation
import HearthKit

/// App-Group store for Goodnight automation configuration.
public enum GoodnightStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let configKey = "goodnight.config"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Loads the Goodnight configuration.
    /// Returns `.default` if the key is absent or the stored JSON is corrupt.
    public static func load() -> GoodnightConfig {
        guard let data = defaults.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(GoodnightConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    /// Saves the Goodnight configuration.
    /// Silently fails if encoding fails (should never happen with Codable model).
    public static func save(_ config: GoodnightConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: configKey)
    }
}
