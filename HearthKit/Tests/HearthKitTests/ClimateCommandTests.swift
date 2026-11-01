import XCTest
@testable import HearthKit

final class ClimateCommandTests: XCTestCase {
    private static let state = ClimateState(mode: "heat", action: "idle", current: 69, humidity: nil,
        target: 68, low: nil, high: nil, fanMode: "auto", fanModes: ["auto", "on"],
        modes: ["off", "heat", "cool"], min: 50, max: 90, step: 1, lastChanged: nil)

    func testSetpointAndChoicePayloadsUseTheBoundEntity() {
        let heat = climateCommand(Self.state, entityID: "climate.room", action: "heatUp")
        XCTAssertEqual(heat?.entityID, "climate.room")
        XCTAssertEqual(heat?.temperatures, ["temperature": 69])
        let mode = climateCommand(Self.state, entityID: "climate.room", action: "mode", option: "cool")
        XCTAssertEqual(mode?.service, "set_hvac_mode")
        XCTAssertEqual(mode?.option, "cool")
        XCTAssertNil(climateCommand(Self.state, entityID: "climate.room", action: "mode", option: "dry"))
        XCTAssertNil(climateCommand(Self.state, entityID: "climate.room", action: "mode", option: "heat"))
        XCTAssertNil(climateCommand(Self.state, entityID: "climate.room", action: "fan", option: "turbo"))
        XCTAssertNil(climateCommand(Self.state, entityID: "climate.room", action: "wrong"))
        XCTAssertNil(climateCommand(Self.state, entityID: "switch.other", action: "heatUp"))
    }

    func testResumeRequiresTheBoundButtonAndAvailableThermostat() {
        XCTAssertNil(climateCommand(Self.state, entityID: "climate.room", action: "resume", resumeID: "script.other"))
        let resume = climateCommand(Self.state, entityID: "climate.room", action: "resume", resumeID: "button.resume")
        XCTAssertEqual(resume?.entityID, "button.resume")
        XCTAssertEqual(resume?.service, "press")
        var unavailable = Self.state; unavailable.mode = "unavailable"
        XCTAssertNil(climateCommand(unavailable, entityID: "climate.room", action: "resume", resumeID: "button.resume"))
    }

    func testUnknownActionAndOldScopeNeverReadOrSend() async throws {
        for (action, current) in [("wrong", true), ("heatUp", false)] {
            let sent = try await executeClimateAction(entityID: "climate.room", action: action,
                isCurrent: { current }, read: { XCTFail("Rejected before reading"); return Self.state },
                send: { _ in XCTFail("No command expected") })
            XCTAssertFalse(sent)
        }
    }

    func testScopeChangeDuringReadPreventsDispatch() async throws {
        let scope = Scope()
        let sent = try await executeClimateAction(entityID: "climate.room", action: "heatUp",
            isCurrent: { scope.current }, read: { scope.invalidate(); return Self.state },
            send: { _ in XCTFail("Old account/entity command must not dispatch") })
        XCTAssertFalse(sent)
    }

    func testAvailableChoiceDispatchesOnlyAfterTheLiveRead() async throws {
        let recorder = Commands()
        let sent = try await executeClimateAction(entityID: "climate.room", action: "fan", option: "on",
            isCurrent: { true }, read: { Self.state }, send: { await recorder.add($0) })
        XCTAssertTrue(sent)
        let commands = await recorder.values
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.service, "set_fan_mode")
        XCTAssertEqual(commands.first?.optionKey, "fan_mode")
        XCTAssertEqual(commands.first?.option, "on")
    }
    func testDirectionalRawModeChangeCannotChangeSingleVersusRangeMeaning() async throws {
        let recorder = Commands()
        let sent = try await executeClimateAction(entityID: "climate.room", action: "heatUp",
            expectedMode: "heat_cool", isCurrent: { true }, read: { Self.state },
            send: { await recorder.add($0) })
        XCTAssertFalse(sent)
        let commands = await recorder.values
        XCTAssertTrue(commands.isEmpty)
    }
}

private actor Commands {
    var values: [ClimateCommand] = []
    func add(_ command: ClimateCommand) { values.append(command) }
}

private final class Scope: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var current: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); defer { lock.unlock() }; valid = false }
}
