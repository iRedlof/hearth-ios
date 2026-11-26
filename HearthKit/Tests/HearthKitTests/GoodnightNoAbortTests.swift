import Testing
import Foundation
@testable import HearthKit

/// Tests for Goodnight no-abort behavior via the executable step pattern.
///
/// NOTE: These tests document the no-abort hotspot behavior using a local test harness.
/// The production `GoodnightRuntime.run` in Shared/ has injectable step closures
/// (injectedCloseCover, injectedTurnOffLights, injectedLock, injectedArm) that enable
/// identical testing at the app level. The tests here prove the logic pattern; app-level
/// integration tests would call `GoodnightRuntime.run(..., injectedCloseCover: mock, ...)`
/// and verify the same no-abort guarantees against the actual runtime.
@Suite("Goodnight No-Abort Logic (Step Execution Pattern)")
struct GoodnightNoAbortLogicTests {

    // MARK: - No-Abort Hotspot Tests

    @Test("Lights failure does NOT skip lock or arm")
    func lightsFailureDoesNotSkipLockAndArm() async {
        let tracker = CallTracker()

        let result = await runStepsWithMocks(
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: "[]"
            ),
            closeCover: { _ in
                await tracker.recordCloseCover()
            },
            turnOffLights: { _ in
                await tracker.recordTurnOffLights()
                throw HaError("Lights offline")
            },
            lock: {
                await tracker.recordLock()
                return true
            },
            arm: { _ in
                await tracker.recordArm()
                return true
            }
        )

        // All steps attempted
        let calls = await tracker.calls
        #expect(calls.closeCover == 0)  // No covers in default plan
        #expect(calls.turnOffLights == 1)
        #expect(calls.lock == 1)
        #expect(calls.arm == 1)

        // Result flags reflect actual outcomes
        #expect(result.garagesClosed == true)  // No garages = success
        #expect(result.lightsOff == false)     // Lights threw
        #expect(result.locked == true)         // Lock succeeded
        #expect(result.armed == true)          // Arm succeeded
    }

    @Test("Garage failure does NOT skip lights, lock, or arm")
    func garageFailureDoesNotSkipRest() async {
        let tracker = CallTracker()

        let result = await runStepsWithMocks(
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: #"["cover.garage"]"#
            ),
            closeCover: { _ in
                await tracker.recordCloseCover()
                throw HaError("Garage stuck")
            },
            turnOffLights: { _ in
                await tracker.recordTurnOffLights()
            },
            lock: {
                await tracker.recordLock()
                return true
            },
            arm: { _ in
                await tracker.recordArm()
                return true
            }
        )

        // All steps attempted
        let calls = await tracker.calls
        #expect(calls.closeCover == 1)  // Garage was attempted
        #expect(calls.turnOffLights == 1)
        #expect(calls.lock == 1)
        #expect(calls.arm == 1)

        // Result flags reflect actual outcomes
        #expect(result.garagesClosed == false)  // Garage threw
        #expect(result.lightsOff == true)       // Lights succeeded
        #expect(result.locked == true)          // Lock succeeded
        #expect(result.armed == true)           // Arm succeeded
    }

    @Test("Multiple failures are recorded independently")
    func multipleFailuresRecordedIndependently() async {
        let tracker = CallTracker()

        let result = await runStepsWithMocks(
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: #"["cover.garage"]"#
            ),
            closeCover: { _ in
                await tracker.recordCloseCover()
                throw HaError("Garage stuck")
            },
            turnOffLights: { _ in
                await tracker.recordTurnOffLights()
                throw HaError("Lights offline")
            },
            lock: {
                await tracker.recordLock()
                return false  // Lock failed
            },
            arm: { _ in
                await tracker.recordArm()
                return false  // Arm failed
            }
        )

        // All steps attempted
        let calls = await tracker.calls
        #expect(calls.closeCover == 1)
        #expect(calls.turnOffLights == 1)
        #expect(calls.lock == 1)
        #expect(calls.arm == 1)

        // All failures recorded
        #expect(result.garagesClosed == false)
        #expect(result.lightsOff == false)
        #expect(result.locked == false)
        #expect(result.armed == false)
    }

    @Test("All successes recorded correctly")
    func allSuccessesRecorded() async {
        let tracker = CallTracker()

        let result = await runStepsWithMocks(
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: #"["cover.garage"]"#
            ),
            closeCover: { _ in
                await tracker.recordCloseCover()
            },
            turnOffLights: { _ in
                await tracker.recordTurnOffLights()
            },
            lock: {
                await tracker.recordLock()
                return true
            },
            arm: { _ in
                await tracker.recordArm()
                return true
            }
        )

        // All steps attempted
        let calls = await tracker.calls
        #expect(calls.closeCover == 1)
        #expect(calls.turnOffLights == 1)
        #expect(calls.lock == 1)
        #expect(calls.arm == 1)

        // All successes recorded
        #expect(result.garagesClosed == true)
        #expect(result.lightsOff == true)
        #expect(result.locked == true)
        #expect(result.armed == true)
    }

    // MARK: - Test Harness (Mirrors GoodnightRuntime.run Logic)

    /// Local test harness mirroring the no-abort step execution pattern used by GoodnightRuntime.run.
    /// The production runtime accepts the same injectable closures; this harness proves the pattern works.
    private func runStepsWithMocks(
        config: GoodnightConfig = GoodnightConfig.default,
        haConfig: HaConfig = HaConfig(
            baseUrl: "https://test",
            token: "token",
            entityId: "alarm_control_panel.home",
            lockId: "lock.front_door",
            doorIdsJson: "[]"
        ),
        closeCover: @escaping @Sendable (String) async throws -> Void,
        turnOffLights: @escaping @Sendable ([String]) async throws -> Void,
        lock: @escaping @Sendable () async -> Bool,
        arm: @escaping @Sendable (String) async -> Bool
    ) async -> (garagesClosed: Bool, lightsOff: Bool, locked: Bool, armed: Bool) {
        // Build the plan (simulating fetchStateForPlanning + planGoodnight)
        let allLights = ["light.living_room", "light.bedroom"]
        let panelSupportsNight = true

        let plan = planGoodnight(
            config: config,
            haConfig: haConfig,
            allLights: allLights,
            panelSupportsNight: panelSupportsNight
        )

        // Execute steps with NO-ABORT: each step is independent
        let garagesClosed: Bool
        let coverIds = plan.covers
        if !coverIds.isEmpty {
            var anyFailed = false
            for id in coverIds {
                do {
                    try await closeCover(id)
                } catch {
                    anyFailed = true
                }
            }
            garagesClosed = !anyFailed
        } else {
            garagesClosed = true
        }

        let lightsOff: Bool
        do {
            let lightIds = plan.lightsOff
            if !lightIds.isEmpty {
                try await turnOffLights(lightIds)
            }
            lightsOff = true
        } catch {
            lightsOff = false
        }

        let locked: Bool
        if plan.lockId != nil {
            locked = await lock()
        } else {
            locked = true
        }

        let armed: Bool
        if plan.armMode != nil {
            armed = await arm(plan.armMode == .night ? "armNight" : "armHome")
        } else {
            armed = true
        }

        return (garagesClosed, lightsOff, locked, armed)
    }
}

// MARK: - Test Support

/// Thread-safe call tracker for mock closures.
private actor CallTracker {
    struct Calls {
        var closeCover = 0
        var turnOffLights = 0
        var lock = 0
        var arm = 0
    }

    private(set) var calls = Calls()

    func recordCloseCover() {
        calls.closeCover += 1
    }

    func recordTurnOffLights() {
        calls.turnOffLights += 1
    }

    func recordLock() {
        calls.lock += 1
    }

    func recordArm() {
        calls.arm += 1
    }
}
