import Foundation
import HearthKit

/// Result of a Goodnight execution with per-step success flags.
public struct GoodnightResult: Sendable, Equatable {
    public let garagesClosed: Bool
    public let lightsOff: Bool
    public let locked: Bool
    public let armed: Bool

    public init(garagesClosed: Bool, lightsOff: Bool, locked: Bool, armed: Bool) {
        self.garagesClosed = garagesClosed
        self.lightsOff = lightsOff
        self.locked = locked
        self.armed = armed
    }
}

/// Sequential Goodnight executor: runs all steps best-effort, never aborting on failure.
public enum GoodnightRuntime {
    /// Executes Goodnight automation: close garages, turn off lights, lock, arm.
    ///
    /// **NO-ABORT:** Each step is wrapped so a failure does NOT prevent subsequent steps.
    /// The safety-critical lock + arm MUST run even if garage or lights fail.
    ///
    /// - Parameters:
    ///   - config: User's Goodnight configuration.
    ///   - haConfig: Home Assistant configuration.
    ///   - now: Current date/time (for logging/context).
    /// - Returns: Per-step success flags.
    public static func run(config: GoodnightConfig, haConfig: HaConfig, now: Date) async -> GoodnightResult {
        // Fetch all lights and alarm state to build the plan
        let (allLights, panelSupportsNight) = await fetchStateForPlanning(haConfig: haConfig)

        // Build the plan
        let plan = planGoodnight(
            config: config,
            haConfig: haConfig,
            allLights: allLights,
            panelSupportsNight: panelSupportsNight
        )

        // Execute each step, capturing specific values before async closures
        // CRITICAL: Each step is independent; failures do NOT abort the sequence

        // Step 1: Close garage covers
        // Best-effort per cover: attempt ALL covers even if one fails
        let garagesClosed: Bool
        let coverIds = plan.covers
        if !coverIds.isEmpty {
            var anyFailed = false
            for id in coverIds {
                do {
                    try await closeCover(id: id, config: haConfig)
                } catch {
                    anyFailed = true
                }
            }
            garagesClosed = !anyFailed
        } else {
            garagesClosed = true
        }

        // Step 2: Turn off lights
        let lightsOff: Bool
        do {
            let lightIds = plan.lightsOff
            if !lightIds.isEmpty {
                try await turnOffLights(ids: lightIds, config: haConfig)
            }
            lightsOff = true
        } catch {
            lightsOff = false
        }

        // Step 3: Lock
        let locked: Bool
        if let lockId = plan.lockId {
            locked = await performLockAction(entityID: lockId, haConfig: haConfig)
        } else {
            locked = true  // No lock configured = not applicable = success
        }

        // Step 4: Arm
        let armed: Bool
        if let armMode = plan.armMode {
            let action = armModeToAction(armMode)
            armed = await performArmAction(entityID: haConfig.entityId, action: action, haConfig: haConfig)
        } else {
            armed = true  // No alarm configured = not applicable = success
        }

        return GoodnightResult(garagesClosed: garagesClosed, lightsOff: lightsOff, locked: locked, armed: armed)
    }

    /// Fetches HA state for planning: all lights and panel Night support.
    /// Returns empty lights and false Night support on failure.
    private static func fetchStateForPlanning(haConfig: HaConfig) async -> ([String], Bool) {
        do {
            let client = HaClient(haConfig)
            let statesJson = try await client.allStatesJson()
            let entities = parseEntities(statesJson)
            let allLights = entities.filter { $0.id.hasPrefix("light.") }.map(\.id)

            // Check if panel supports Night mode (bit 2: supported_features & 4 != 0)
            let panelSupportsNight: Bool
            if haConfig.entityId.hasPrefix("alarm_control_panel.") {
                let alarmStateJson = try await client.stateJson(haConfig.entityId)
                let alarmState = AlarmState.fromJson(alarmStateJson)
                panelSupportsNight = alarmState?.supportedFeatures.map { $0 & 4 != 0 } ?? false
            } else {
                panelSupportsNight = false
            }
            return (allLights, panelSupportsNight)
        } catch {
            // If we can't fetch state, default to no lights and no Night support
            return ([], false)
        }
    }

    /// Performs a lock action via the existing AlarmActionRuntime path.
    /// Returns true on success, false on failure.
    private static func performLockAction(entityID: String, haConfig: HaConfig) async -> Bool {
        let client = HaClient(haConfig)
        let isCurrent: @Sendable () -> Bool = { true }  // Goodnight runs unconditionally
        do {
            let result = try await executeAlarmAction(
                entityID: entityID,
                action: "lock",
                isCurrent: isCurrent,
                read: {
                    let json = try await client.stateJson(entityID)
                    guard AlarmState.fromJson(json)?.entityID == entityID else {
                        throw HaError("Couldn't read lock")
                    }
                    return HaStateReading(entityID: entityID, json: json, checkedAt: Date())
                },
                send: { command in
                    try await client.callService(domain: command.domain, service: command.service, entityId: command.entityID)
                },
                wait: { try await Task.sleep(for: .seconds(2)) }
            )
            return result == .confirmed
        } catch {
            return false
        }
    }

    /// Performs an arm action via the existing AlarmActionRuntime path.
    /// Returns true on success, false on failure.
    private static func performArmAction(entityID: String, action: String, haConfig: HaConfig) async -> Bool {
        let client = HaClient(haConfig)
        let isCurrent: @Sendable () -> Bool = { true }  // Goodnight runs unconditionally
        do {
            let result = try await executeAlarmAction(
                entityID: entityID,
                action: action,
                isCurrent: isCurrent,
                read: {
                    let json = try await client.stateJson(entityID)
                    guard AlarmState.fromJson(json)?.entityID == entityID else {
                        throw HaError("Couldn't read alarm panel")
                    }
                    return HaStateReading(entityID: entityID, json: json, checkedAt: Date())
                },
                send: { command in
                    try await client.callService(domain: command.domain, service: command.service, entityId: command.entityID)
                },
                wait: { try await Task.sleep(for: .seconds(2)) }
            )
            return result == .confirmed
        } catch {
            return false
        }
    }

    /// Maps GoodnightArmMode to AlarmAction string.
    private static func armModeToAction(_ mode: GoodnightArmMode) -> String {
        switch mode {
        case .night: return "armNight"
        case .home: return "armHome"
        }
    }
}
