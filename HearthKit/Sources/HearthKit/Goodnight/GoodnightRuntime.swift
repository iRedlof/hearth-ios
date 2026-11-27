import Foundation

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
    ///   - injectedFetchState: Optional injected closure for fetching HA state (for testing). Returns (allLights, panelSupportsNight).
    ///   - injectedCloseCover: Optional injected closure for closing covers (for testing).
    ///   - injectedTurnOffLights: Optional injected closure for turning off lights (for testing).
    ///   - injectedLock: Optional injected closure for locking (for testing).
    ///   - injectedArm: Optional injected closure for arming (for testing).
    ///   - injectedRecord: Optional injected closure for recording action history (for testing). Defaults to ActionHistoryStore.record.
    /// - Returns: Per-step success flags.
    public static func run(
        config: GoodnightConfig,
        haConfig: HaConfig,
        now: Date,
        injectedFetchState: (@Sendable (HaConfig) async -> ([String], Bool))? = nil,
        injectedCloseCover: (@Sendable (String) async throws -> Void)? = nil,
        injectedTurnOffLights: (@Sendable ([String]) async throws -> Void)? = nil,
        injectedLock: (@Sendable () async -> Bool)? = nil,
        injectedArm: (@Sendable (String) async -> Bool)? = nil,
        injectedRecord: (@Sendable (ActionHistoryRecord) -> Void)? = nil
    ) async -> GoodnightResult {
        // Fetch all lights and alarm state to build the plan
        let (allLights, panelSupportsNight) = if let injected = injectedFetchState {
            await injected(haConfig)
        } else {
            await fetchStateForPlanning(haConfig: haConfig)
        }

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
                    if let injected = injectedCloseCover {
                        try await injected(id)
                    } else {
                        try await closeCover(id: id, config: haConfig)
                    }
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
                if let injected = injectedTurnOffLights {
                    try await injected(lightIds)
                } else {
                    try await turnOffLights(ids: lightIds, config: haConfig)
                }
            }
            lightsOff = true
        } catch {
            lightsOff = false
        }

        // Step 3: Lock
        let locked: Bool
        if let lockId = plan.lockId {
            if let injected = injectedLock {
                locked = await injected()
            } else {
                locked = await performLockAction(entityID: lockId, haConfig: haConfig)
            }
        } else {
            locked = true  // No lock configured = not applicable = success
        }

        // Step 4: Arm
        let armed: Bool
        if let armMode = plan.armMode {
            let action = armModeToAction(armMode)
            if let injected = injectedArm {
                armed = await injected(action)
            } else {
                armed = await performArmAction(entityID: haConfig.entityId, action: action, haConfig: haConfig)
            }
        } else {
            armed = true  // No alarm configured = not applicable = success
        }

        let result = GoodnightResult(garagesClosed: garagesClosed, lightsOff: lightsOff, locked: locked, armed: armed)

        // Record action history if all safety-critical steps succeeded (Routines learning hook)
        // This runs AFTER the outcome is decided and must NEVER delay or throw into the execution path.
        // If all 4 steps succeeded, record the action-set for routine learning.
        if result.garagesClosed && result.lightsOff && result.locked && result.armed {
            // Capture specific values before the recording closure (Sendable compliance)
            let allLightsCaptured = allLights
            let coverIdsCaptured = plan.covers
            let lockIdCaptured = plan.lockId
            let alarmIdCaptured = haConfig.entityId

            // Build the action-set in execution order
            let actionSet = config.actionSet(
                allLights: allLightsCaptured,
                garageIDs: coverIdsCaptured,
                lockID: lockIdCaptured,
                alarmID: alarmIdCaptured
            )

            let entry = ActionHistoryRecord(timestamp: now, entityIDs: actionSet)

            if let record = injectedRecord {
                // Test path: call injected spy
                record(entry)
            } else {
                // Production path: record to ActionHistoryStore
                // Swallow any recording failure (it's local UserDefaults, best-effort only).
                // We already succeeded at the safety-critical operations; recording failure must not affect that outcome.
                ActionHistoryStore.record(entry, now: now)
            }
        }

        return result
    }

    /// Fetches HA state for planning: all lights and panel Night support.
    ///
    /// **Decoupled fetches:** Lights and panel capability are fetched independently. A panel-read
    /// failure does NOT discard successfully fetched lights, and does NOT downgrade Night→Home
    /// (the preferred mode remains authoritative; if HA later rejects Night, the arm step will record
    /// a real failure rather than silently arming the weaker Home mode).
    ///
    /// - Returns: (allLights, panelSupportsNight) where:
    ///   - allLights: empty on fetch failure, otherwise all `light.*` entity IDs
    ///   - panelSupportsNight: true if we couldn't read the panel (assume Night capable) OR
    ///     if the panel actually supports Night; false only if we successfully read a panel that
    ///     lacks Night support.
    private static func fetchStateForPlanning(haConfig: HaConfig) async -> ([String], Bool) {
        let client = HaClient(haConfig)

        // Fetch 1: All lights (independent)
        let allLights: [String]
        do {
            let statesJson = try await client.allStatesJson()
            let entities = parseEntities(statesJson)
            allLights = entities.filter { $0.id.hasPrefix("light.") }.map(\.id)
        } catch {
            allLights = []
        }

        // Fetch 2: Panel Night capability (independent)
        let panelSupportsNight: Bool
        if haConfig.entityId.hasPrefix("alarm_control_panel.") {
            do {
                let alarmStateJson = try await client.stateJson(haConfig.entityId)
                let alarmState = AlarmState.fromJson(alarmStateJson)
                panelSupportsNight = alarmState?.supportedFeatures.map { $0 & 4 != 0 } ?? false
            } catch {
                // Panel read failed: treat as Night-capable (don't downgrade Night→Home).
                // If HA rejects Night at arm time, that's an honest failure, not a silent downgrade.
                panelSupportsNight = true
            }
        } else {
            panelSupportsNight = false
        }

        return (allLights, panelSupportsNight)
    }

    /// Performs a lock action via the existing AlarmActionRuntime path.
    /// Returns true on success, false on failure.
    ///
    /// **Reduced confirmation budget:** Lock-screen intents have tight execution windows.
    /// Uses 3 confirmation attempts (6s) instead of the interactive default (10 attempts = 20s)
    /// to fit lock + arm within the OS's intent budget.
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
                wait: { try await Task.sleep(for: .seconds(2)) },
                confirmationAttempts: 3  // Reduced for lock-screen intent (vs default 10)
            )
            return result == .confirmed
        } catch {
            return false
        }
    }

    /// Performs an arm action via the existing AlarmActionRuntime path.
    /// Returns true on success, false on failure.
    ///
    /// **Reduced confirmation budget:** Lock-screen intents have tight execution windows.
    /// Uses 3 confirmation attempts (6s) instead of the interactive default (10 attempts = 20s)
    /// to fit lock + arm within the OS's intent budget.
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
                wait: { try await Task.sleep(for: .seconds(2)) },
                confirmationAttempts: 3  // Reduced for lock-screen intent (vs default 10)
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
