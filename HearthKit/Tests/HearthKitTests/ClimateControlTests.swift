import XCTest
@testable import HearthKit

final class ClimateControlTests: XCTestCase {
    private func st(mode: String, target: Double? = nil, low: Double? = nil, high: Double? = nil,
                    min: Double = 50, max: Double = 90, step: Double = 1) -> ClimateState {
        ClimateState(mode: mode, action: nil, current: 70, humidity: nil, target: target, low: low, high: high,
                     fanMode: nil, fanModes: [], modes: [], min: min, max: max, step: step, lastChanged: nil)
    }

    // The existing nudge: step within limits, and in Auto keep heat a step below cool.
    func testNudgeStepsAndClamps() {
        let s = st(mode: "heat", target: 68)
        XCTAssertEqual(nudge(68, by: 1, s), 69)
        XCTAssertEqual(nudge(68, by: -1, s), 67)
        XCTAssertEqual(nudge(90, by: 1, s), 90)   // clamp at max
        XCTAssertEqual(nudge(50, by: -1, s), 50)  // clamp at min
    }

    func testSetpointNudgeSingleModeSendsTemperature() {
        let s = st(mode: "heat", target: 68)
        XCTAssertEqual(setpointNudge(s, side: .heat, by: 1), ["temperature": 69])
    }

    func testSetpointNudgeRangeKeepsOtherEnd() {
        let s = st(mode: "heat_cool", low: 64, high: 70)
        XCTAssertEqual(setpointNudge(s, side: .heat, by: 1), ["target_temp_low": 65, "target_temp_high": 70])
        XCTAssertEqual(setpointNudge(s, side: .cool, by: -1), ["target_temp_low": 64, "target_temp_high": 69])
    }

    func testSetpointNudgeNilWhenIncomplete() {
        XCTAssertNil(setpointNudge(st(mode: "heat_cool", low: nil, high: 70), side: .heat, by: 1))
    }

    func testInvalidLimitsAndTargetsNeverFormCommands() {
        let invalid = [
            st(mode: "heat", target: 68, step: 0),
            st(mode: "heat", target: 68, step: -0.5),
            st(mode: "heat", target: 68, min: 90, max: 50),
            st(mode: "heat", target: .infinity),
            st(mode: "heat", target: 1e300),
            st(mode: "heat_cool", low: 50, high: 50),
            st(mode: "heat_cool", low: 70, high: 64),
            st(mode: "heat_cool", low: 49, high: 70),
            st(mode: "heat_cool", low: 64, high: 91)
        ]
        for state in invalid {
            XCTAssertFalse(state.canSetTemperature, "\(state)")
            XCTAssertNil(setpointNudge(state, side: .heat, by: -1))
            XCTAssertNil(setpointNudge(state, side: .cool, by: 1))
        }
    }

    func testBoundedAndWrongSideButtonsDoNotSendNoOpOrWrongTarget() {
        XCTAssertNil(setpointNudge(st(mode: "heat", target: 68), side: .cool, by: 1))
        XCTAssertNil(setpointNudge(st(mode: "cool", target: 68), side: .heat, by: 1))
        XCTAssertNil(setpointNudge(st(mode: "heat", target: 90), side: .heat, by: 1))
        XCTAssertNil(setpointNudge(st(mode: "heat", target: 50), side: .heat, by: -1))
        XCTAssertNil(setpointNudge(st(mode: "heat", target: 68), side: .heat, by: 0))
        XCTAssertNil(setpointNudge(st(mode: "heat", target: 68), side: .heat, by: 2))
        let half = st(mode: "heat_cool", low: 64, high: 70, step: 0.5)
        XCTAssertEqual(setpointNudge(half, side: .heat, by: 1),
                       ["target_temp_low": 64.5, "target_temp_high": 70])
        XCTAssertEqual(setpointNudge(half, side: .cool, by: -1),
                       ["target_temp_low": 64, "target_temp_high": 69.5])
    }

    func testModeAndFanCommandsUseAvailableDistinctOptions() {
        var state = st(mode: "heat", target: 68)
        state.modes = ["", "heat", "heat", "unknown", "cool", "unavailable"]
        state.fanMode = "auto"; state.fanModes = ["auto", "", "on", "on"]
        XCTAssertEqual(climateNextOption(state, kind: "mode"), "cool")
        XCTAssertEqual(climateNextOption(state, kind: "fan"), "on")
        XCTAssertNil(climateNextOption(state, kind: "wrong"))
        state.mode = "unavailable"
        XCTAssertNil(climateNextOption(state, kind: "mode"))
        XCTAssertNil(climateNextOption(state, kind: "fan"))
        state.mode = "heat"; state.modes = ["heat"]
        XCTAssertNil(climateNextOption(state, kind: "mode"))
    }

    func testOneDifferentOptionRemainsSelectableAndSentinelsCannotBeSent() {
        var state = st(mode: "heat", target: 68)
        state.fanMode = "on"
        state.fanModes = [" unknown ", "Unavailable ", " null", " auto ", "auto"]
        XCTAssertEqual(climateOptions(state, kind: "fan"), ["auto"])
        XCTAssertEqual(climateNextOption(state, kind: "fan"), "auto")
        state.modes = ["heat", " unknown ", "not_a_mode", "cool"]
        XCTAssertEqual(climateOptions(state, kind: "mode"), ["heat", "cool"])
    }
}
