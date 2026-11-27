import Testing
import Foundation
@testable import HearthKit

@Suite("Routines Recording Integration Tests")
struct RoutinesRecordingTests {
    // MARK: - GoodnightRuntime Recording Tests

    @Test("GoodnightRuntime records action-set on successful run")
    func testGoodnightRecordsOnSuccess() async {
        // Setup: test suite with injected success closures
        let now = Date()
        let config = GoodnightConfig(
            enabled: true,
            startHour: 22,
            endHour: 6,
            armMode: .night,
            keepOnLights: []
        )
        let haConfig = HaConfig(
            baseUrl: "http://test.local",
            token: "token",
            entityId: "alarm_control_panel.panel",
            lockId: "lock.front"
        )

        // Spy: capture recorded action-set (using actor for Sendable compliance)
        final class RecordSpy: @unchecked Sendable {
            var entityIDs: [String]?
            var timestamp: Date?
            func record(_ record: ActionHistoryRecord) {
                entityIDs = record.entityIDs
                timestamp = record.timestamp
            }
        }
        let spy = RecordSpy()
        let recordSpy: @Sendable (ActionHistoryRecord) -> Void = { record in
            spy.record(record)
        }

        // Execute: all steps succeed
        let result = await GoodnightRuntime.run(
            config: config,
            haConfig: haConfig,
            now: now,
            injectedFetchState: { _ in (["light.kitchen", "light.den"], true) },
            injectedCloseCover: { _ in },
            injectedTurnOffLights: { _ in },
            injectedLock: { true },
            injectedArm: { _ in true },
            injectedRecord: recordSpy
        )

        // Verify: all steps succeeded
        #expect(result.garagesClosed == true)
        #expect(result.lightsOff == true)
        #expect(result.locked == true)
        #expect(result.armed == true)

        // Verify: recorded exactly one entry with correct action-set
        #expect(spy.entityIDs != nil)
        #expect(spy.timestamp != nil)

        // Expected action-set: lights (kitchen, den) + lock + alarm
        let expectedActionSet = ["light.kitchen", "light.den", "lock.front", "alarm_control_panel.panel"]
        #expect(spy.entityIDs == expectedActionSet)
        #expect(spy.timestamp == now)
    }

    @Test("GoodnightRuntime does NOT record when arm fails")
    func testGoodnightDoesNotRecordOnArmFailure() async {
        let now = Date()
        let config = GoodnightConfig(enabled: true, startHour: 22, endHour: 6, armMode: .night, keepOnLights: [])
        let haConfig = HaConfig(
            baseUrl: "http://test.local",
            token: "token",
            entityId: "alarm_control_panel.panel",
            lockId: "lock.front"
        )

        final class CallCounter: @unchecked Sendable {
            var count = 0
            func increment() { count += 1 }
        }
        let counter = CallCounter()
        let recordSpy: @Sendable (ActionHistoryRecord) -> Void = { _ in
            counter.increment()
        }

        // Execute: arm step FAILS
        let result = await GoodnightRuntime.run(
            config: config,
            haConfig: haConfig,
            now: now,
            injectedFetchState: { _ in (["light.kitchen"], true) },
            injectedCloseCover: { _ in },
            injectedTurnOffLights: { _ in },
            injectedLock: { true },
            injectedArm: { _ in false },  // Arm FAILS
            injectedRecord: recordSpy
        )

        // Verify: arm failed
        #expect(result.armed == false)

        // Verify: NO recording happened
        #expect(counter.count == 0)
    }

    @Test("GoodnightRuntime does NOT record when lock fails")
    func testGoodnightDoesNotRecordOnLockFailure() async {
        let now = Date()
        let config = GoodnightConfig(enabled: true, startHour: 22, endHour: 6, armMode: .night, keepOnLights: [])
        let haConfig = HaConfig(
            baseUrl: "http://test.local",
            token: "token",
            entityId: "alarm_control_panel.panel",
            lockId: "lock.front"
        )

        final class CallCounter: @unchecked Sendable {
            var count = 0
            func increment() { count += 1 }
        }
        let counter = CallCounter()
        let recordSpy: @Sendable (ActionHistoryRecord) -> Void = { _ in
            counter.increment()
        }

        // Execute: lock step FAILS
        let result = await GoodnightRuntime.run(
            config: config,
            haConfig: haConfig,
            now: now,
            injectedFetchState: { _ in (["light.kitchen"], true) },
            injectedCloseCover: { _ in },
            injectedTurnOffLights: { _ in },
            injectedLock: { false },  // Lock FAILS
            injectedArm: { _ in true },
            injectedRecord: recordSpy
        )

        // Verify: lock failed
        #expect(result.locked == false)

        // Verify: NO recording happened
        #expect(counter.count == 0)
    }
}
