import Testing
import Foundation
@testable import HearthKit

/// Tests for Goodnight no-abort behavior by calling production `GoodnightRuntime.run()`
/// with fully injected dependencies (state fetch + step execution). No reimplementation.
@Suite("Goodnight No-Abort Hotspot (Production Runtime)")
struct GoodnightNoAbortTests {

    // MARK: - No-Abort Hotspot Tests

    @Test("Lights failure does NOT skip lock or arm")
    func lightsFailureDoesNotSkipLockAndArm() async {
        let tracker = CallTracker()

        let result = await GoodnightRuntime.run(
            config: GoodnightConfig.default,
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: "[]"
            ),
            now: Date(),
            injectedFetchState: { _ in
                (["light.living_room", "light.bedroom"], true)
            },
            injectedCloseCover: { _ in
                await tracker.recordCloseCover()
            },
            injectedTurnOffLights: { _ in
                await tracker.recordTurnOffLights()
                throw HaError("Lights offline")
            },
            injectedLock: {
                await tracker.recordLock()
                return true
            },
            injectedArm: { _ in
                await tracker.recordArm()
                return true
            }
        )

        // All steps attempted
        let calls = await tracker.calls
        #expect(calls.closeCover == 0)  // No covers in plan
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

        let result = await GoodnightRuntime.run(
            config: GoodnightConfig.default,
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: #"["cover.garage"]"#
            ),
            now: Date(),
            injectedFetchState: { _ in
                (["light.living_room", "light.bedroom"], true)
            },
            injectedCloseCover: { _ in
                await tracker.recordCloseCover()
                throw HaError("Garage stuck")
            },
            injectedTurnOffLights: { _ in
                await tracker.recordTurnOffLights()
            },
            injectedLock: {
                await tracker.recordLock()
                return true
            },
            injectedArm: { _ in
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

        let result = await GoodnightRuntime.run(
            config: GoodnightConfig.default,
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: #"["cover.garage"]"#
            ),
            now: Date(),
            injectedFetchState: { _ in
                (["light.living_room", "light.bedroom"], true)
            },
            injectedCloseCover: { _ in
                await tracker.recordCloseCover()
                throw HaError("Garage stuck")
            },
            injectedTurnOffLights: { _ in
                await tracker.recordTurnOffLights()
                throw HaError("Lights offline")
            },
            injectedLock: {
                await tracker.recordLock()
                return false  // Lock failed
            },
            injectedArm: { _ in
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

        let result = await GoodnightRuntime.run(
            config: GoodnightConfig.default,
            haConfig: HaConfig(
                baseUrl: "https://test",
                token: "token",
                entityId: "alarm_control_panel.home",
                lockId: "lock.front_door",
                doorIdsJson: #"["cover.garage"]"#
            ),
            now: Date(),
            injectedFetchState: { _ in
                (["light.living_room", "light.bedroom"], true)
            },
            injectedCloseCover: { _ in
                await tracker.recordCloseCover()
            },
            injectedTurnOffLights: { _ in
                await tracker.recordTurnOffLights()
            },
            injectedLock: {
                await tracker.recordLock()
                return true
            },
            injectedArm: { _ in
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
