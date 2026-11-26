import Foundation

/// App-Group store for Goodnight automation configuration.
public enum GoodnightStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let configKey = "goodnight.config"

    private static var defaultDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Loads the Goodnight configuration.
    /// Returns `.default` if the key is absent or the stored JSON is corrupt.
    ///
    /// - Parameter defaults: Optional UserDefaults instance for testing. Defaults to app-group suite.
    public static func load(defaults: UserDefaults? = nil) -> GoodnightConfig {
        let store = defaults ?? defaultDefaults
        guard let data = store.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(GoodnightConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    /// Saves the Goodnight configuration.
    /// Silently fails if encoding fails (should never happen with Codable model).
    ///
    /// - Parameters:
    ///   - config: The configuration to save.
    ///   - defaults: Optional UserDefaults instance for testing. Defaults to app-group suite.
    public static func save(_ config: GoodnightConfig, defaults: UserDefaults? = nil) {
        let store = defaults ?? defaultDefaults
        guard let data = try? JSONEncoder().encode(config) else { return }
        store.set(data, forKey: configKey)
    }
}
