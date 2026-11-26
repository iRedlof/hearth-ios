import XCTest
@testable import HearthKit

final class AlarmCommandTests: XCTestCase {
    private static func reading(_ state: String, entity: String = "alarm_control_panel.home",
                                features: Int = 3) -> HaStateReading {
        HaStateReading(entityID: entity,
            json: "{\"entity_id\":\"\(entity)\",\"state\":\"\(state)\",\"attributes\":{\"supported_features\":\(features),\"code_format\":\"number\",\"code_arm_required\":true}}",
            checkedAt: Date(timeIntervalSince1970: 100))
    }

    func testExactPayloadAndDefaultCodeCompatibility() throws {
        for (action, state, entity, domain, service, target) in [
            ("armHome", "disarmed", "alarm_control_panel.home", "alarm_control_panel", "alarm_arm_home", "armed_home"),
            ("armAway", "disarmed", "alarm_control_panel.home", "alarm_control_panel", "alarm_arm_away", "armed_away"),
            ("disarm", "pending", "alarm_control_panel.home", "alarm_control_panel", "alarm_disarm", "disarmed"),
            ("lock", "jammed", "lock.door", "lock", "lock", "locked"),
            ("unlock", "locked", "lock.door", "lock", "unlock", "unlocked")
        ] {
            let command = try XCTUnwrap(alarmCommand(Self.reading(state, entity: entity), entityID: entity, action: action))
            XCTAssertEqual(command.domain, domain)
            XCTAssertEqual(command.service, service)
            XCTAssertEqual(command.entityID, entity)
            XCTAssertEqual(command.target, target)
        }
    }

    func testMalformedIdentityUnknownStateAndLiveCapabilitiesCannotEnableDispatch() {
        XCTAssertNil(alarmCommand(Self.reading("disarmed", features: 0), entityID: "alarm_control_panel.home", action: "armHome"))
        XCTAssertNil(alarmCommand(Self.reading("disarmed", features: 1), entityID: "alarm_control_panel.home", action: "armAway"))
        XCTAssertNil(alarmCommand(Self.reading("locked", entity: "lock.other"), entityID: "lock.door", action: "unlock"))
        XCTAssertNil(alarmCommand(Self.reading("unavailable"), entityID: "alarm_control_panel.home", action: "disarm"))
        XCTAssertNil(alarmCommand(Self.reading("locking", entity: "lock.door"), entityID: "lock.door", action: "unlock"))
        XCTAssertNil(alarmCommand(Self.reading("disarmed"), entityID: "alarm_control_panel.home", action: "lock"))
        XCTAssertNil(alarmCommand(Self.reading("armed_home"), entityID: "alarm_control_panel.home", action: "armAway"))
    }

    func testRejectedActionAndObsoleteOriginNeverReadOrSend() async throws {
        for (action, current) in [("wrong", true), ("disarm", false)] {
            let result = try await executeAlarmAction(entityID: "alarm_control_panel.home", action: action,
                isCurrent: { current }, read: { XCTFail("Must reject before reading"); return Self.reading("armed_home") },
                send: { _ in XCTFail("No service call") }, wait: {})
            XCTAssertNotEqual(result, .confirmed)
        }
    }

    func testSelectionChangeDuringPreflightPreventsPost() async throws {
        let origin = AlarmTestOrigin()
        let result = try await executeAlarmAction(entityID: "alarm_control_panel.home", action: "disarm",
            isCurrent: { origin.current }, read: { origin.invalidate(); return Self.reading("armed_home") },
            send: { _ in XCTFail("Old target must not be commanded") }, wait: {})
        XCTAssertEqual(result, .obsolete)
    }

    func testAcknowledgementAndTransitionsDoNotConfirmDisarm() async throws {
        let transport = AlarmTestTransport(["armed_home", "pending", "arming", "disarming", "disarmed"].map { Self.reading($0) })
        let result = try await executeAlarmAction(entityID: "alarm_control_panel.home", action: "disarm",
            isCurrent: { true }, read: { try await transport.read() }, send: { await transport.send($0) },
            observe: { await transport.observe($0) }, wait: {}, confirmationAttempts: 4)
        XCTAssertEqual(result, .confirmed)
        let calls = await transport.commands
        let observations = await transport.observations
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(observations.map { AlarmState.fromJson($0.json)?.state },
                       ["armed_home", "pending", "arming", "disarming", "disarmed"])
    }

    func testUnconfirmedCommandIsNeverResent() async throws {
        let transport = AlarmTestTransport((0..<4).map { _ in Self.reading("disarmed") })
        let result = try await executeAlarmAction(entityID: "alarm_control_panel.home", action: "armHome",
            isCurrent: { true }, read: { try await transport.read() }, send: { await transport.send($0) },
            wait: {}, confirmationAttempts: 3)
        XCTAssertEqual(result, .unconfirmed)
        let calls = await transport.commands
        XCTAssertEqual(calls.count, 1)
    }

    func testAlreadyAchievedTargetDoesNotSendAnotherCommand() async throws {
        let result = try await executeAlarmAction(entityID: "lock.door", action: "lock",
            isCurrent: { true }, read: { Self.reading("locked", entity: "lock.door") },
            send: { _ in XCTFail("Already locked") }, wait: {})
        XCTAssertEqual(result, .confirmed)
    }

    func testWrongConfirmationEntityCannotConfirmOrUpdateTelemetry() async throws {
        let transport = AlarmTestTransport([Self.reading("armed_home"), Self.reading("disarmed", entity: "alarm_control_panel.other")])
        do {
            _ = try await executeAlarmAction(entityID: "alarm_control_panel.home", action: "disarm",
                isCurrent: { true }, read: { try await transport.read() }, send: { await transport.send($0) },
                observe: { await transport.observe($0) }, wait: {}, confirmationAttempts: 1)
            XCTFail("Wrong response must fail")
        } catch {}
        let calls = await transport.commands, observations = await transport.observations
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(observations.count, 1)
    }

    func testCancelledPreflightDoesNotSendAndCancelledPollDoesNotRetry() async throws {
        for cancelInPoll in [false, true] {
            let transport = AlarmTestTransport([Self.reading("armed_home")])
            let task = Task {
                try await executeAlarmAction(entityID: "alarm_control_panel.home", action: "disarm",
                    isCurrent: { true },
                    read: {
                        if !cancelInPoll { throw CancellationError() }
                        return try await transport.read()
                    }, send: { await transport.send($0) },
                    wait: { throw CancellationError() })
            }
            do { _ = try await task.value; XCTFail("Cancellation must propagate") } catch is CancellationError {} catch { XCTFail("\(error)") }
            let calls = await transport.commands
            XCTAssertEqual(calls.count, cancelInPoll ? 1 : 0)
        }
    }

    func testOriginInvalidationAfterPostOrDuringPollCannotConfirmOrResend() async throws {
        for point in ["post", "read", "observe"] {
            let origin = AlarmTestOrigin()
            let transport = AlarmTestTransport([Self.reading("armed_home"), Self.reading("disarmed")])
            let result = try await executeAlarmAction(entityID: "alarm_control_panel.home", action: "disarm",
                isCurrent: { origin.current },
                read: {
                    let value = try await transport.read()
                    if point == "read", AlarmState.fromJson(value.json)?.state == "disarmed" { origin.invalidate() }
                    return value
                },
                send: {
                    await transport.send($0)
                    if point == "post" { origin.invalidate() }
                },
                observe: {
                    await transport.observe($0)
                    if point == "observe", AlarmState.fromJson($0.json)?.state == "disarmed" { origin.invalidate() }
                }, wait: {}, confirmationAttempts: 1)
            XCTAssertEqual(result, .obsolete)
            let calls = await transport.commands
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testUncertainPostFailureNeverRetriesOrStartsConfirmationReads() async throws {
        let transport = AlarmTestTransport([Self.reading("armed_home")])
        do {
            _ = try await executeAlarmAction(entityID: "alarm_control_panel.home", action: "disarm",
                isCurrent: { true }, read: { try await transport.read() },
                send: { await transport.send($0); throw HaError("Connection lost after send") },
                wait: { XCTFail("Uncertain service delivery must not retry") })
            XCTFail("Failure must propagate")
        } catch {}
        let calls = await transport.commands
        XCTAssertEqual(calls.count, 1)
    }
}

private actor AlarmTestTransport {
    var replies: [HaStateReading]
    var commands: [AlarmCommand] = []
    var observations: [HaStateReading] = []
    init(_ replies: [HaStateReading]) { self.replies = replies }
    func read() throws -> HaStateReading {
        guard !replies.isEmpty else { throw HaError("No more fixture replies") }
        return replies.removeFirst()
    }
    func send(_ command: AlarmCommand) { commands.append(command) }
    func observe(_ reading: HaStateReading) { observations.append(reading) }
}

private final class AlarmTestOrigin: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var current: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); defer { lock.unlock() }; valid = false }
}
