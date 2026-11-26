import Foundation

/// A concrete Goodnight execution plan with all steps resolved.
public struct GoodnightPlan: Sendable, Equatable {
    /// Cover entity IDs to close (e.g., garage doors).
    public let covers: [String]
    /// Light entity IDs to turn off.
    public let lightsOff: [String]
    /// Lock entity ID to lock (nil if no lock configured).
    public let lockId: String?
    /// Resolved arm mode (after Night→Home fallback if needed).
    public let armMode: GoodnightArmMode?

    public init(covers: [String], lightsOff: [String], lockId: String?, armMode: GoodnightArmMode?) {
        self.covers = covers
        self.lightsOff = lightsOff
        self.lockId = lockId
        self.armMode = armMode
    }
}

/// Builds a Goodnight execution plan from config and HA state.
///
/// - Parameters:
///   - config: User's Goodnight configuration.
///   - haConfig: Home Assistant configuration (door/lock/alarm IDs).
///   - allLights: All `light.*` entity IDs from HA.
///   - panelSupportsNight: Whether the alarm panel supports Night mode (check bit 2: `supportedFeatures & 4 != 0`).
/// - Returns: A concrete plan with resolved steps (covers, lights, lock, arm).
public func planGoodnight(
    config: GoodnightConfig,
    haConfig: HaConfig,
    allLights: [String],
    panelSupportsNight: Bool
) -> GoodnightPlan {
    // 1. Garage covers: filter doorIds to `cover.*` only
    let covers = haConfig.doorIds.filter { $0.hasPrefix("cover.") }

    // 2. Lights off: all lights minus keep-on
    let lightsOff = lightsToTurnOff(all: allLights, keepOn: config.keepOnLights)

    // 3. Lock: use haConfig.lockId if present and valid
    let lockId = haConfig.lockId.hasPrefix("lock.") ? haConfig.lockId : nil

    // 4. Arm mode: resolve Night→Home fallback, nil if no alarm configured
    let armMode: GoodnightArmMode?
    if haConfig.entityId.hasPrefix("alarm_control_panel.") {
        armMode = resolveArmMode(preferred: config.armMode, panelSupportsNight: panelSupportsNight)
    } else {
        armMode = nil
    }

    return GoodnightPlan(covers: covers, lightsOff: lightsOff, lockId: lockId, armMode: armMode)
}
