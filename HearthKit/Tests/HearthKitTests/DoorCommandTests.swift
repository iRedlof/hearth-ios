import XCTest
@testable import HearthKit

final class DoorCommandTests: XCTestCase {
    private static let time = Date(timeIntervalSince1970: 1_000)
    private static func reading(_ state: String, entity: String = "cover.garage",
                                rawEntity: String? = nil, deviceClass: String = "garage",
                                features: String? = "11", at: Date = Date(timeIntervalSince1970: 1_000)) -> HaStateReading {
        let flags = features.map { ",\"supported_features\":\($0)" } ?? ""
        return HaStateReading(entityID: entity,
            json: "{\"entity_id\":\"\(rawEntity ?? entity)\",\"state\":\"\(state)\",\"attributes\":{\"device_class\":\"\(deviceClass)\"\(flags)}}",
            checkedAt: at)
    }

    func testLiveGarageAndLockStatesProduceExactServiceTargets() throws {
        for (state, entity, action, domain, service) in [
            ("closed", "cover.garage", "open", "cover", "open_cover"),
            ("open", "cover.gate", "close", "cover", "close_cover"),
            ("opening", "cover.garage", "stop", "cover", "stop_cover"),
            ("closing", "cover.garage", "stop", "cover", "stop_cover"),
            ("closed", "cover.garage", "stop", "cover", "stop_cover"),
            ("unlocked", "lock.front", "lock", "lock", "lock")
        ] {
            let command = try XCTUnwrap(doorCommand(Self.reading(state, entity: entity),
                entityID: entity, action: action, now: Self.time))
            XCTAssertEqual(command.entityID, entity)
            XCTAssertEqual(command.domain, domain)
            XCTAssertEqual(command.service, service)
            XCTAssertEqual(command.action.rawValue, action)
        }
    }

    func testWrongEntityAndUnrelatedDomainsCannotSupplyACommandReading() {
        for reading in [
            Self.reading("closed", entity: "cover.other"),
            Self.reading("closed", rawEntity: "cover.other"),
            Self.reading("closed", deviceClass: "blind"),
            Self.reading("closed", entity: "switch.garage")
        ] {
            XCTAssertNil(doorCommandObservation(reading, entityID: "cover.garage", now: Self.time))
        }
        XCTAssertNil(doorCommand(Self.reading("off", entity: "binary_sensor.front", deviceClass: "door"),
            entityID: "binary_sensor.front", action: "open", now: Self.time))
        XCTAssertNil(doorCommand(Self.reading("unlocked", entity: "lock.front"),
            entityID: "lock.front", action: "open", now: Self.time))
    }

    func testStaleFutureUnknownAndUnsupportedReadingsDoNotEnableDispatch() {
        for reading in [
            Self.reading("closed", at: Self.time.addingTimeInterval(-901)),
            Self.reading("closed", at: Self.time.addingTimeInterval(1)),
            Self.reading("unknown"), Self.reading("unavailable"),
            Self.reading("opening"), Self.reading("closed", features: "0"),
            Self.reading("closed", features: "true"), Self.reading("closed", features: "\"11\"")
        ] {
            XCTAssertNil(doorCommand(reading, entityID: "cover.garage", action: "open", now: Self.time))
        }
        XCTAssertNotNil(doorCommand(Self.reading("closed", at: Self.time.addingTimeInterval(-900)),
            entityID: "cover.garage", action: "open", now: Self.time))
        XCTAssertNotNil(doorCommand(Self.reading("closed", features: nil),
            entityID: "cover.garage", action: "open", now: Self.time))
    }

    func testObsoleteOriginAndInvalidActionRejectBeforeReadOrClaim() async throws {
        for (action, current) in [("wrong", true), ("open", false)] {
            let result = try await executeDoorAction(entityID: "cover.garage", action: action,
                isCurrent: { current }, claimDispatch: { XCTFail("Must not claim"); return true },
                read: { XCTFail("Must not read"); return Self.reading("closed") },
                send: { _ in XCTFail("Must not send") }, wait: {}, now: { Self.time })
            XCTAssertEqual(result, current ? .rejected : .obsolete)
        }
    }

    func testSelectionChangeDuringPreflightCannotClaimOrSend() async throws {
        let origin = DoorTestOrigin()
        let result = try await executeDoorAction(entityID: "cover.garage", action: "open",
            isCurrent: { origin.current }, claimDispatch: { XCTFail("Old origin cannot claim"); return true },
            read: { origin.invalidate(); return Self.reading("closed") },
            send: { _ in XCTFail("Old origin cannot send") }, wait: {}, now: { Self.time })
        XCTAssertEqual(result, .obsolete)
    }

    func testAlreadyAchievedTargetDoesNotClaimOrSendAgain() async throws {
        for (entity, state, action) in [("cover.garage", "open", "open"), ("lock.front", "locked", "lock")] {
            let result = try await executeDoorAction(entityID: entity, action: action,
                isCurrent: { true }, claimDispatch: { XCTFail("Already achieved"); return true },
                read: { Self.reading(state, entity: entity) },
                send: { _ in XCTFail("Already achieved") }, wait: {}, now: { Self.time })
            XCTAssertEqual(result, .confirmed)
        }
    }

    func testRejectedOrLostDispatchClaimCannotSend() async throws {
        for losingOrigin in [false, true] {
            let origin = DoorTestOrigin()
            let result = try await executeDoorAction(entityID: "cover.garage", action: "open",
                isCurrent: { origin.current },
                claimDispatch: { if losingOrigin { origin.invalidate() }; return losingOrigin },
                read: { Self.reading("closed") }, send: { _ in XCTFail("Claim was lost") },
                wait: {}, now: { Self.time })
            XCTAssertEqual(result, .obsolete)
        }
    }

    func testHttpAcknowledgementAndMovementNeverConfirmOpenOrCauseResend() async throws {
        let transport = DoorTestTransport(["closed", "opening", "opening", "open"].map { Self.reading($0) })
        let claims = DoorTestClaim()
        let result = try await executeDoorAction(entityID: "cover.garage", action: "open",
            isCurrent: { true }, claimDispatch: { claims.claim() },
            read: { try await transport.read() }, send: { await transport.send($0) },
            observe: { await transport.observe($0) }, wait: {}, now: { Self.time }, confirmationAttempts: 3)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(claims.count, 1)
        let commands = await transport.commands, observations = await transport.observations
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(observations.map { doorFromState($0.json)?.state }, ["closed", "opening", "opening", "open"])
    }

    func testUnconfirmedCommandRetainsOneDispatch() async throws {
        let transport = DoorTestTransport(["closed", "opening", "opening"].map { Self.reading($0) })
        let result = try await executeDoorAction(entityID: "cover.garage", action: "open",
            isCurrent: { true }, claimDispatch: { true }, read: { try await transport.read() },
            send: { await transport.send($0) }, wait: {}, now: { Self.time }, confirmationAttempts: 2)
        XCTAssertEqual(result, .unconfirmed)
        let commands = await transport.commands
        XCTAssertEqual(commands.count, 1)
    }

    func testStopDispatchesEvenIfEarlierCommandHasNotStartedMovingAndNeedsLaterRestingRead() async throws {
        for initial in ["closed", "opening", "closing", "open"] {
            let transport = DoorTestTransport([initial, "opening", "closed"].map { Self.reading($0) })
            let result = try await executeDoorAction(entityID: "cover.garage", action: "stop",
                isCurrent: { true }, claimDispatch: { true }, read: { try await transport.read() },
                send: { await transport.send($0) }, wait: {}, now: { Self.time }, confirmationAttempts: 2)
            XCTAssertEqual(result, .confirmed)
            let commands = await transport.commands
            XCTAssertEqual(commands.map(\.service), ["stop_cover"])
        }
    }

    func testInvalidConfirmationCannotConfirmOrReplaceCurrentTelemetry() async throws {
        for reply in [
            Self.reading("open", rawEntity: "cover.other"),
            Self.reading("open", at: Self.time.addingTimeInterval(-1)),
            Self.reading("unknown")
        ] {
            let transport = DoorTestTransport([Self.reading("closed"), reply])
            do {
                _ = try await executeDoorAction(entityID: "cover.garage", action: "open",
                    isCurrent: { true }, claimDispatch: { true }, read: { try await transport.read() },
                    send: { await transport.send($0) }, observe: { await transport.observe($0) },
                    wait: {}, now: { Self.time }, confirmationAttempts: 1)
                XCTFail("Invalid confirmation must fail")
            } catch {}
            let commands = await transport.commands, observations = await transport.observations
            XCTAssertEqual(commands.count, 1)
            XCTAssertEqual(observations.count, 1)
        }
    }

    func testCancellationBeforeAndAfterPostPropagatesWithoutRetry() async throws {
        for cancelDuringWait in [false, true] {
            let transport = DoorTestTransport([Self.reading("closed")])
            do {
                _ = try await executeDoorAction(entityID: "cover.garage", action: "open",
                    isCurrent: { true }, claimDispatch: { true },
                    read: {
                        if !cancelDuringWait { throw CancellationError() }
                        return try await transport.read()
                    }, send: { await transport.send($0) },
                    wait: { throw CancellationError() }, now: { Self.time })
                XCTFail("Cancellation must propagate")
            } catch is CancellationError {} catch { XCTFail("\(error)") }
            let commands = await transport.commands
            XCTAssertEqual(commands.count, cancelDuringWait ? 1 : 0)
        }
    }

    func testLostOriginAfterPostOrDuringObservationCannotConfirmOrResend() async throws {
        for point in ["post", "read", "observe"] {
            let origin = DoorTestOrigin()
            let transport = DoorTestTransport([Self.reading("closed"), Self.reading("open")])
            let result = try await executeDoorAction(entityID: "cover.garage", action: "open",
                isCurrent: { origin.current }, claimDispatch: { true },
                read: {
                    let reading = try await transport.read()
                    if point == "read", doorFromState(reading.json)?.state == "open" { origin.invalidate() }
                    return reading
                },
                send: { await transport.send($0); if point == "post" { origin.invalidate() } },
                observe: {
                    await transport.observe($0)
                    if point == "observe", doorFromState($0.json)?.state == "open" { origin.invalidate() }
                }, wait: {}, now: { Self.time }, confirmationAttempts: 1)
            XCTAssertEqual(result, .obsolete)
            let commands = await transport.commands
            XCTAssertEqual(commands.count, 1)
        }
    }

    func testUncertainPostFailureDoesNotRetryOrStartConfirmation() async throws {
        let transport = DoorTestTransport([Self.reading("closed")])
        do {
            _ = try await executeDoorAction(entityID: "cover.garage", action: "open",
                isCurrent: { true }, claimDispatch: { true }, read: { try await transport.read() },
                send: { await transport.send($0); throw HaError("Connection lost after send") },
                wait: { XCTFail("No retry after uncertain delivery") }, now: { Self.time })
            XCTFail("Delivery uncertainty must propagate")
        } catch {}
        let commands = await transport.commands
        XCTAssertEqual(commands.count, 1)
    }

    func testOwnedStopTakeoverCanDispatchFromFreshUnknownTelemetry() async throws {
        for state in ["unknown", "unavailable"] {
            let transport = DoorTestTransport([Self.reading(state), Self.reading("open")])
            let claims = DoorTestClaim()
            let result = try await executeDoorAction(entityID: "cover.garage", action: "stop",
                ownedStopTakeover: true, isCurrent: { true }, claimDispatch: { claims.claim() },
                read: { try await transport.read() }, send: { await transport.send($0) },
                observe: { await transport.observe($0) }, wait: {}, now: { Self.time }, confirmationAttempts: 1)
            XCTAssertEqual(result, .confirmed)
            XCTAssertEqual(claims.count, 1)
            let commands = await transport.commands, observations = await transport.observations
            XCTAssertEqual(commands.map(\.service), ["stop_cover"])
            XCTAssertEqual(observations.map { doorFromState($0.json)?.state }, [state, "open"])
        }
    }

    func testOwnedStopTakeoverCannotConfirmUnknownPostTelemetry() async throws {
        for state in ["unknown", "unavailable"] {
            let transport = DoorTestTransport([Self.reading(state), Self.reading(state)])
            do {
                let result = try await executeDoorAction(entityID: "cover.garage", action: "stop",
                    ownedStopTakeover: true, isCurrent: { true }, claimDispatch: { true },
                    read: { try await transport.read() }, send: { await transport.send($0) },
                    wait: {}, now: { Self.time }, confirmationAttempts: 1)
                XCTAssertNotEqual(result, .confirmed)
            } catch {}
            let commands = await transport.commands
            XCTAssertEqual(commands.map(\.service), ["stop_cover"])
        }
    }

    func testOwnedStopStillRejectsWrongStaleOrUnsupportedTelemetry() async throws {
        for reading in [
            Self.reading("unknown", entity: "cover.other"),
            Self.reading("unknown", rawEntity: "cover.other"),
            Self.reading("unknown", deviceClass: "blind"),
            Self.reading("unknown", at: Self.time.addingTimeInterval(-901)),
            Self.reading("unknown", at: Self.time.addingTimeInterval(1)),
            Self.reading("unknown", features: "3"),
            Self.reading("unknown", features: "true"),
            Self.reading("unknown", features: "\"11\"")
        ] {
            do {
                let result = try await executeDoorAction(entityID: "cover.garage", action: "stop",
                    ownedStopTakeover: true, isCurrent: { true },
                    claimDispatch: { XCTFail("Invalid telemetry cannot claim"); return true },
                    read: { reading }, send: { _ in XCTFail("Invalid telemetry cannot dispatch") },
                    wait: {}, now: { Self.time }, confirmationAttempts: 0)
                XCTAssertNotEqual(result, .confirmed)
            } catch {}
        }
    }

    func testOrdinaryUnknownControlsRemainInertWhenTakeoverFlagIsPresent() async throws {
        for (entity, action, owned) in [
            ("cover.garage", "stop", false),
            ("cover.garage", "open", true),
            ("cover.garage", "close", true),
            ("lock.front", "lock", true)
        ] {
            do {
                let result = try await executeDoorAction(entityID: entity, action: action,
                    ownedStopTakeover: owned, isCurrent: { true },
                    claimDispatch: { XCTFail("Ordinary unknown control cannot claim"); return true },
                    read: { Self.reading("unknown", entity: entity) },
                    send: { _ in XCTFail("Ordinary unknown control cannot dispatch") },
                    wait: {}, now: { Self.time }, confirmationAttempts: 0)
                XCTAssertNotEqual(result, .confirmed)
            } catch {}
        }
    }
}

private actor DoorTestTransport {
    var replies: [HaStateReading]
    var commands: [DoorCommand] = []
    var observations: [HaStateReading] = []
    init(_ replies: [HaStateReading]) { self.replies = replies }
    func read() throws -> HaStateReading {
        guard !replies.isEmpty else { throw HaError("No fixture reading remains") }
        return replies.removeFirst()
    }
    func send(_ command: DoorCommand) { commands.append(command) }
    func observe(_ reading: HaStateReading) { observations.append(reading) }
}

private final class DoorTestOrigin: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var current: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); defer { lock.unlock() }; valid = false }
}

private final class DoorTestClaim: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return claimed }
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        claimed += 1
        return claimed == 1
    }
}
