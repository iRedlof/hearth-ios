import XCTest
@testable import HearthKit

final class CarAvailabilityTests: XCTestCase {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let loc = Locale(identifier: "en_US")
    var now: Date { parseOffsetDateTime("2026-10-14T09:30:00Z")! }

    func rawReply(_ s: [String: String], tempUnit: String = "°F", pressureUnit: String = "psi") -> String {
        let o: [String: Any] = ["found": true, "name": "Stargate", "unit": "mi",
                                "tempUnit": tempUnit, "pressureUnit": pressureUnit, "s": s, "statusSince": NSNull()]
        return String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }

    func test1_unavailableTelemetryNotReportedAsOffShut() {
        let c = carFromTemplate(rawReply([
            "sensor.battery_level": "57", "switch.sentry_mode": "unavailable",
            "binary_sensor.charge_cable": "unknown", "lock.lock": "locking",
        ]))!
        XCTAssertFalse(c.sentryKnown)
        XCTAssertFalse(c.pluggedKnown)
        XCTAssertFalse(c.openKnown)
        XCTAssertNil(c.locked)
        let v = carView(c, now: now, zone: zone, locale: loc)
        XCTAssertFalse(v.charge.hasPrefix("Not plugged"))
        XCTAssertFalse(v.facts.contains { $0.text == "All shut" })
    }

    func test2_knownOpenTrunkThoughAnotherUnknown() {
        let c = carFromTemplate(rawReply([
            "sensor.battery_level": "57", "cover.trunk": "open",
            "switch.sentry_mode": "off", "binary_sensor.charge_cable": "off",
        ]))!
        XCTAssertTrue(c.sentryKnown)
        XCTAssertTrue(c.pluggedKnown)
        XCTAssertFalse(c.openKnown)
        XCTAssertEqual(c.open, ["Trunk"])
        XCTAssertEqual(carView(c, now: now, zone: zone, locale: loc).tone, .warn)
    }

    func test3_pressureKeepsDecimalsForBar() {
        let c = carFromTemplate(rawReply([
            "sensor.battery_level": "57",
            "sensor.tire_pressure_front_left": "2.7", "sensor.tire_pressure_front_right": "2.8",
            "sensor.tire_pressure_rear_left": "2.6", "sensor.tire_pressure_rear_right": "2.7",
        ], pressureUnit: "bar"))!
        XCTAssertEqual(c.preciseTires, [2.7, 2.8, 2.6, 2.7])
        XCTAssertEqual(beaconTireSummary(c), "2.6\u{2013}2.8 bar")
    }

    func test4_celsiusKeepsDecimalsUnknownStaysUnknown() {
        let c = carFromTemplate(rawReply([
            "sensor.battery_level": "57",
            "sensor.inside_temperature": "21.5", "sensor.outside_temperature": "-2.5",
        ], tempUnit: "°C"))!
        XCTAssertEqual(c.preciseInside, 21.5)
        XCTAssertEqual(c.preciseOutside, -2.5)
    }

    func test5_nonfiniteCantBecomeHugeValues() {
        let c = carFromTemplate(rawReply([
            "sensor.battery_level": "NaN", "number.charge_limit": "Infinity",
            "sensor.inside_temperature": "Infinity",
        ]))!
        XCTAssertNil(c.battery)
        XCTAssertNil(c.limit)
        XCTAssertNil(c.inside)
    }
}
