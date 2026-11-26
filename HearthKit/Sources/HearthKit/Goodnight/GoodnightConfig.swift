import Foundation

/// Arm mode for Goodnight automation.
public enum GoodnightArmMode: String, Sendable, Codable, Equatable {
    case night
    case home
}

/// Configuration for Goodnight automation: sleep-time auto-arming + keep-on lights.
public struct GoodnightConfig: Sendable, Codable, Equatable {
    /// Whether Goodnight automation is enabled.
    public var enabled: Bool
    /// Start hour (0–23) for the Goodnight window.
    public var startHour: Int
    /// End hour (0–23) for the Goodnight window.
    public var endHour: Int
    /// Arm mode to apply during Goodnight.
    public var armMode: GoodnightArmMode
    /// Entity IDs of lights to keep on (not turn off).
    public var keepOnLights: [String]

    public init(
        enabled: Bool = false,
        startHour: Int = 21,
        endHour: Int = 5,
        armMode: GoodnightArmMode = .night,
        keepOnLights: [String] = []
    ) {
        self.enabled = enabled
        self.startHour = startHour
        self.endHour = endHour
        self.armMode = armMode
        self.keepOnLights = keepOnLights
    }

    /// Default configuration: disabled, 21:00→5:00, night mode, no keep-on lights.
    public static let `default` = GoodnightConfig()
}
