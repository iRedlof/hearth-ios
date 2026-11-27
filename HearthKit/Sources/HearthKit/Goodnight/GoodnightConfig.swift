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

    /// Returns the action-set entity IDs in Goodnight execution order: garages, lights (filtered by keepOn), lock, alarm.
    /// Used for Routines matching to determine if a learned routine matches Goodnight's key.
    ///
    /// - Parameter allLights: All available light entity IDs (from HA state fetch).
    /// - Parameter garageIDs: All garage cover entity IDs.
    /// - Parameter lockID: The lock entity ID, if configured.
    /// - Parameter alarmID: The alarm panel entity ID, if configured.
    /// - Returns: Entity IDs in execution order: covers → lights-off (minus keepOn) → lock → alarm.
    public func actionSet(
        allLights: [String] = [],
        garageIDs: [String] = [],
        lockID: String? = nil,
        alarmID: String? = nil
    ) -> [String] {
        var result: [String] = []

        // 1. Garage covers
        result.append(contentsOf: garageIDs)

        // 2. Lights to turn off (all lights minus keepOn)
        let lightsOff = allLights.filter { !keepOnLights.contains($0) }
        result.append(contentsOf: lightsOff)

        // 3. Lock
        if let lock = lockID {
            result.append(lock)
        }

        // 4. Alarm
        if let alarm = alarmID {
            result.append(alarm)
        }

        return result
    }
}
