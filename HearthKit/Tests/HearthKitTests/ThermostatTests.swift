import XCTest
@testable import HearthKit

final class ThermostatTests: XCTestCase {
    let thermo = """
    {"entity_id":"climate.thermo","state":"heat_cool","last_changed":"2026-10-12T20:00:00+00:00","attributes":{
    "current_humidity":54.0,"current_temperature":69,"fan_mode":"on","fan_modes":["on","auto"],"hvac_action":"fan",
    "hvac_modes":["off","heat","cool","heat_cool"],"max_temp":75,"min_temp":63,"target_temp_high":69,"target_temp_low":64,"temperature":null}}
    """

    func testReadsTheEcobee() {
        let s = ClimateState.fromJson(thermo)!
        XCTAssertEqual(s.mode, "heat_cool")
        XCTAssertEqual(s.action, "fan")
        XCTAssertEqual(s.current, 69.0)
        XCTAssertEqual(s.low, 64.0)
        XCTAssertEqual(s.high, 69.0)
        XCTAssertNil(s.target)
        XCTAssertEqual(s.fanModes, ["on", "auto"])
        XCTAssertTrue(s.isRange)
    }

    func testSaysWhatItsDoing() {
        let s = ClimateState.fromJson(thermo)!
        XCTAssertEqual(climateViewFor(s), ClimateView("Fan only · set 64–69°", .idle))
        var heating = s; heating.action = "heating"
        XCTAssertEqual(climateViewFor(heating), ClimateView("Heating to 64°", .heating))
        var cooling = s; cooling.action = "cooling"
        XCTAssertEqual(climateViewFor(cooling), ClimateView("Cooling to 69°", .cooling))
        var idle = s; idle.action = "idle"
        XCTAssertEqual(climateViewFor(idle), ClimateView("Holding 64–69°", .idle))
        var heat = s; heat.mode = "heat"; heat.target = 68.0; heat.action = "heating"
        XCTAssertEqual(climateViewFor(heat), ClimateView("Heating to 68°", .heating))
        var off = s; off.mode = "off"
        XCTAssertEqual(climateViewFor(off), ClimateView("Off", .off))
        XCTAssertEqual(climateViewFor(nil), ClimateView("Checking…", .unknown))
    }

    func testOffResidualHeatingCooling() {
        var off = ClimateState.fromJson(thermo)!; off.mode = "off"
        var i = off; i.action = "idle"; XCTAssertEqual(climateViewFor(i), ClimateView("Off", .off))
        var o = off; o.action = "off"; XCTAssertEqual(climateViewFor(o), ClimateView("Off", .off))
        var h = off; h.action = "heating"; XCTAssertEqual(climateViewFor(h), ClimateView("Off · still heating", .off))
        var c = off; c.action = "cooling"; XCTAssertEqual(climateViewFor(c), ClimateView("Off · still cooling", .off))
    }

    func testFanOnly() {
        var s = ClimateState.fromJson(thermo)!; s.mode = "fan_only"; s.action = "fan"
        XCTAssertEqual(climateViewFor(s), ClimateView("Fan only", .idle))
    }

    func testDry() {
        var s = ClimateState.fromJson(thermo)!; s.mode = "dry"; s.action = "drying"
        XCTAssertEqual(climateViewFor(s), ClimateView("Dry", .idle))
    }

    func testUnknownTargetsNoEmptyRange() {
        var s = ClimateState.fromJson(thermo)!; s.action = "idle"; s.low = nil; s.high = nil
        XCTAssertEqual(climateViewFor(s).headline, "Targets unavailable")
        var a = s; a.high = 69.0; XCTAssertEqual(climateViewFor(a).headline, "Heat target unavailable")
        var b = s; b.low = 64.0; XCTAssertEqual(climateViewFor(b).headline, "Cool target unavailable")
        var c = s; c.mode = "heat"; c.target = nil; XCTAssertEqual(climateViewFor(c).headline, "Target unavailable")
    }

    func testInvalidTargetsCannotBecomeAHoldingHeadline() {
        var state = ClimateState.fromJson(thermo)!
        state.action = "idle"
        state.low = 1e300
        XCTAssertEqual(climateViewFor(state).headline, "Heat target unavailable")
        state.low = 64; state.high = .nan
        XCTAssertEqual(climateViewFor(state).headline, "Cool target unavailable")
        state.mode = "heat"; state.target = .infinity
        XCTAssertEqual(climateViewFor(state).headline, "Target unavailable")
    }

    func testCanSetTemperature() {
        let s = ClimateState.fromJson(thermo)!
        XCTAssertTrue(s.canSetTemperature)
        var a = s; a.low = nil; XCTAssertFalse(a.canSetTemperature)
        var b = s; b.high = nil; XCTAssertFalse(b.canSetTemperature)
        var c = s; c.mode = "heat"; c.target = nil; XCTAssertFalse(c.canSetTemperature)
        var d = s; d.mode = "heat"; d.target = 68.0; XCTAssertTrue(d.canSetTemperature)
        var e = s; e.mode = "fan_only"; e.target = 68.0; XCTAssertFalse(e.canSetTemperature)
    }

    func testNudgeStaysInRangeAndApart() {
        let s = ClimateState.fromJson(thermo)!
        XCTAssertEqual(nudge(64, by: 1, s, otherHigh: 69), 65, accuracy: 0.0001)
        XCTAssertEqual(nudge(68, by: 1, s, otherHigh: 69), 68, accuracy: 0.0001)
        XCTAssertEqual(nudge(63, by: -1, s), 63, accuracy: 0.0001)
        XCTAssertEqual(nudge(75, by: 1, s), 75, accuracy: 0.0001)
        XCTAssertEqual(nudge(65, by: -1, s, otherLow: 64), 65, accuracy: 0.0001)
    }

    func testDegrees() {
        XCTAssertEqual(degrees(69.0), "69°")
        XCTAssertEqual(degrees(69.5), "69.5°")
        XCTAssertEqual(degrees(nil), "—")
        XCTAssertEqual(degrees(.nan), "—")
        XCTAssertEqual(degrees(.infinity), "—")
        XCTAssertEqual(degrees(1e300), "—")
    }

    func testClimateTones() {
        XCTAssertEqual(beaconClimatePair("heat", stale: false).fillARGB, 0xFFF6D58A)
        XCTAssertEqual(beaconClimatePair("cool", stale: false).fillARGB, 0xFFA6D5FF)
        XCTAssertEqual(beaconClimatePair("heat_cool", stale: false).fillARGB, 0xFFC5C3F3)
        XCTAssertEqual(beaconClimatePair("auto", stale: false), beaconClimatePair("heat_cool", stale: false))
        XCTAssertEqual(beaconClimatePair("heat", stale: true).fillARGB, 0xFFBCC2B9)
    }

    func testSnapshotDistinguishesMissingAndStaleRoomReadings() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let missing = thermostatSnapshot(nil, name: "Thermostat", now: now, stale: true, checkedAt: nil)
        XCTAssertEqual(missing.roomSub, "No reading")
        var value = ClimateState.fromJson(thermo)!
        let saved = thermostatSnapshot(value, name: "Thermostat", now: now, stale: true, checkedAt: now, canResume: true)
        XCTAssertEqual(saved.roomSub, "Last known")
        XCTAssertFalse(saved.canResume)
        value.current = nil
        let noRoom = thermostatSnapshot(value, name: "Thermostat", now: now, stale: false, checkedAt: now)
        XCTAssertEqual(noRoom.roomSub, "No reading")
    }

    func testUnavailableTelemetryCannotClaimCurrentRoomOrEnableCommands() throws {
        for mode in ["unavailable", "unknown", "null", "unexpected"] {
            let json = #"{"state":"\#(mode)","attributes":{"current_temperature":67,"temperature":68,"fan_mode":"auto","fan_modes":["auto","on"],"hvac_modes":["off","heat"]}}"#
            let state = try XCTUnwrap(ClimateState.fromJson(json))
            let snapshot = thermostatSnapshot(state, name: "Thermostat", now: .now, stale: false,
                checkedAt: .now, canResume: true)
            XCTAssertEqual(snapshot.status, "Unavailable", mode)
            XCTAssertEqual(snapshot.roomSub, "Last known", mode)
            XCTAssertTrue(snapshot.stale, mode)
            XCTAssertFalse(snapshot.canPickMode, mode)
            XCTAssertFalse(snapshot.canPickFan, mode)
            XCTAssertFalse(snapshot.canResume, mode)
        }
    }

    func testAdvertisedFanRetainsItsSlotWhenUnavailableAndCurrentFanIsMissing() throws {
        for mode in ["unavailable", "unknown"] {
            let json = #"{"state":"\#(mode)","attributes":{"fan_modes":["auto","on"]}}"#
            let state = try XCTUnwrap(ClimateState.fromJson(json))
            let snapshot = thermostatSnapshot(state, name: "Thermostat", now: .now,
                stale: false, checkedAt: .now)
            XCTAssertTrue(snapshot.hasFanControl, mode)
            XCTAssertNil(snapshot.fan, mode)
            XCTAssertFalse(snapshot.canPickFan, mode)
        }
    }
}
