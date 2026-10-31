import XCTest
@testable import HearthKit

final class ClimateFetchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "",
        climateId: "climate.room", resumeId: "button.resume", sensorsJson: #"["sensor.outside","sensor.bedroom"]"#)
    private static func state(_ mode: String = "heat", current: String = "69") -> String {
        """
        {"entity_id":"climate.room","state":"\(mode)","attributes":{"friendly_name":"Hallway",
        "current_temperature":\(current),"temperature":68,"min_temp":50,"max_temp":90,
        "hvac_action":"heating","hvac_modes":["off","heat","cool"],"fan_mode":"auto","fan_modes":["auto","on"]}}
        """
    }
    private static func sensor(_ id: String, _ value: String) -> String {
        #"{"entity_id":"\#(id)","state":"\#(value)","attributes":{"friendly_name":"\#(id)","unit_of_measurement":"°F"}}"#
    }

    func testTypedFailureClassificationDoesNotParseFriendlyMessage() async {
        let cases: [(any Error, HaReadingFailureReason)] = [
            (HaError("arbitrary", code: 401), .authentication),
            (HaError("Sign in", code: 404), .entityNotFound),
            (URLError(.timedOut), .transport),
            (CancellationError(), .interrupted)
        ]
        for (error, expected) in cases {
            let result = await fetchHaStateReadings(config, ids: [config.climateId], now: now) { _ in throw error }
            XCTAssertEqual(result.failureReasons[config.climateId], expected)
        }
    }

    func testMalformedWholeReplyIsFailureButMalformedRoomInValidReplyIsSuccessfulEvidence() async {
        let malformed = await fetchHaStateReadings(config, ids: [config.climateId], now: now) { _ in "{}" }
        XCTAssertNil(malformed.readings[config.climateId])
        XCTAssertEqual(malformed.failureReasons[config.climateId], .malformed)
        let valid = await fetchHaStateReadings(config, ids: [config.climateId], now: now) { _ in
            Self.state(current: "true")
        }
        XCTAssertTrue(valid.errors.isEmpty)
        XCTAssertTrue(valid.failureReasons.isEmpty)
        XCTAssertEqual(valid.readings[config.climateId]?.checkedAt, now)
        XCTAssertNil(valid.readings[config.climateId].flatMap { ClimateState.fromJson($0.json) }?.current)
    }

    func testSetupNeverFetchesOrShowsSample() async {
        let result = await fetchThermostatReadings(nil, now: now) { _ in
            XCTFail("No request in setup"); return Self.state()
        }
        let snap = result.snapshot(now: now)
        XCTAssertTrue(snap.setup)
        XCTAssertEqual(snap.roomTemp, "—")
        XCTAssertEqual(snap.checkedAt, "—")
        XCTAssertFalse(snap.canAdjustHeatUp)
        XCTAssertFalse(snap.canPickMode)
    }

    func testFailureKeepsSuccessfulTimeAndHistoricalTargetsWithoutControls() async {
        let first = await fetchThermostatReadings(config, now: now) { id in
            id.hasPrefix("climate.") ? Self.state() : Self.sensor(id, "72")
        }
        let result = await fetchThermostatReadings(config, previous: first.readings, now: now.addingTimeInterval(60)) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let snap = result.snapshot(now: now)
        XCTAssertEqual(result.readings["climate.room"]?.checkedAt, now)
        XCTAssertEqual(snap.roomTemp, "69°")
        XCTAssertEqual(snap.roomSub, "Last known")
        XCTAssertEqual(snap.status, "Can't connect")
        XCTAssertEqual(snap.error, "Can't reach Home Assistant")
        XCTAssertTrue(snap.stale)
        XCTAssertFalse(snap.canAdjustHeatUp)
        XCTAssertFalse(snap.canResume)
        XCTAssertFalse(snap.canPickMode)
        XCTAssertEqual(snap.sensors.count, 2)
        XCTAssertTrue(snap.sensors.allSatisfy(\.stale))
    }

    func testMalformedAndWrongEntityRepliesDoNotBecomeSuccessfulChecks() async {
        for reply in ["{}", "not json", #"{"state":null}"#,
                      #"{"entity_id":"climate.other","state":"heat"}"#] {
            let result = await fetchThermostatReadings(config, now: now) { _ in reply }
            let snap = result.snapshot(now: now)
            XCTAssertEqual(snap.checkedAt, "—")
            XCTAssertEqual(snap.roomTemp, "—")
            XCTAssertNotNil(snap.error)
        }
    }

    func testOneSensorFailureDoesNotDiscardTheCurrentClimateOrSelectedRow() async {
        let first = await fetchThermostatReadings(config, now: now) { id in
            id.hasPrefix("climate.") ? Self.state() : Self.sensor(id, "72")
        }
        let result = await fetchThermostatReadings(config, previous: first.readings, now: now.addingTimeInterval(60)) { id in
            if id == "sensor.outside" { throw URLError(.timedOut) }
            return id.hasPrefix("climate.") ? Self.state("cool") : Self.sensor(id, "74")
        }
        let snap = result.snapshot(now: now)
        XCTAssertFalse(snap.stale)
        XCTAssertEqual(snap.mode, "Cool")
        XCTAssertEqual(snap.sensors.map(\.id), ["sensor.outside", "sensor.bedroom"])
        XCTAssertTrue(snap.sensors[0].stale)
        XCTAssertEqual(snap.sensors[0].value, "72°")
        XCTAssertFalse(snap.sensors[1].stale)
        XCTAssertEqual(snap.sensors[1].value, "74°")
    }

    func testNonFiniteAndHugeSensorsStayUnknownWithoutTrapping() async {
        for input in ["NaN", "Infinity", "1e300", "unknown", "unavailable"] {
            let result = await fetchThermostatReadings(config, now: now) { id in
                id.hasPrefix("climate.") ? Self.state() : Self.sensor(id, input)
            }
            XCTAssertTrue(result.snapshot(now: now).sensors.allSatisfy { $0.value == "—" })
        }
    }

    func testUnavailableAndPartialTargetsDoNotOfferAdjustment() async {
        let result = await fetchThermostatReadings(config, now: now) { id in
            id.hasPrefix("climate.") ? Self.state("unavailable") : Self.sensor(id, "72")
        }
        let snap = result.snapshot(now: now)
        XCTAssertEqual(snap.status, "Unavailable")
        XCTAssertFalse(snap.canPickMode)
        XCTAssertFalse(snap.canResume)
        let partial = ClimateState(mode: "heat_cool", action: nil, current: 70, humidity: nil,
            target: nil, low: 64, high: nil, fanMode: nil, fanModes: [], modes: ["heat_cool", "off"],
            min: 50, max: 90, step: 1, lastChanged: nil)
        let mapped = thermostatSnapshot(partial, name: "Thermostat", now: now, stale: false, checkedAt: now)
        XCTAssertEqual(mapped.heatSetpoint, "64°")
        XCTAssertFalse(mapped.canAdjustHeatUp)
        XCTAssertFalse(mapped.canAdjustHeatDown)
    }

    func testUnknownSensorKeepsItsFriendlyNameAndUnavailableValue() async {
        let result = await fetchThermostatReadings(config, now: now) { id in
            id.hasPrefix("climate.") ? Self.state() : Self.sensor(id, "unknown")
        }
        XCTAssertEqual(result.snapshot(now: now).sensors.map(\.name), ["sensor.outside", "sensor.bedroom"])
        XCTAssertTrue(result.snapshot(now: now).sensors.allSatisfy { $0.value == "—" })
    }

    func testCurrentSensorsRemainCurrentWhenOnlyClimateFails() async {
        let first = await fetchThermostatReadings(config, now: now) { id in
            id.hasPrefix("climate.") ? Self.state() : Self.sensor(id, "72")
        }
        let second = await fetchThermostatReadings(config, previous: first.readings,
            now: now.addingTimeInterval(60)) { id in
                if id.hasPrefix("climate.") { throw URLError(.timedOut) }
                return Self.sensor(id, "74")
            }
        let snap = second.snapshot(now: now)
        XCTAssertTrue(snap.stale)
        XCTAssertFalse(snap.canAdjustHeatUp)
        XCTAssertEqual(snap.sensors.map(\.value), ["74°", "74°"])
        XCTAssertTrue(snap.sensors.allSatisfy { !$0.stale })
    }

    func testSensorReadingsPreserveReportedDecimalPrecision() async {
        let result = await fetchThermostatReadings(config, now: now) { id in
            id.hasPrefix("climate.") ? Self.state() : Self.sensor(id, "67.5")
        }
        XCTAssertEqual(result.snapshot(now: now).sensors.map(\.value), ["67.5°", "67.5°"])
    }
}
