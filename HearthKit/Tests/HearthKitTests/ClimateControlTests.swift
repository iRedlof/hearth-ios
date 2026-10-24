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
}
