import XCTest
@testable import HearthKit

final class CarNumericBoundsTests: XCTestCase {
    // Finite transport numbers can exceed Int; rejection must happen before compact parsing/formatting.
    func testHugeFiniteBatteryIsAnUnknownReadingInsteadOfTrapping() throws {
        let raw = #"{"found":true,"prefix":"stargate","s":{"sensor.battery_level":"1e100"}}"#
        let car = try XCTUnwrap(carFromTemplate(raw))
        XCTAssertNil(car.battery)
        let snapshot = CarFetchResult(cache: CarReadingsCache(current: raw, lastGood: nil,
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000))).snapshot()
        XCTAssertNil(snapshot.battery)
    }

    // Every parsed numeric field can reach whole-number formatting, including precise tire/temp fields.
    func testUnsupportedMagnitudeCannotReachAnyCompactNumericField() throws {
        let keys = ["sensor.battery_level", "sensor.battery_range", "number.charge_limit",
                    "sensor.charger_power", "sensor.inside_temperature", "sensor.outside_temperature",
                    "sensor.odometer", "sensor.charge_energy_added",
                    "sensor.tire_pressure_front_left", "sensor.tire_pressure_front_right",
                    "sensor.tire_pressure_rear_left", "sensor.tire_pressure_rear_right"]
        for value in ["1e100", "-1e100", "1e308", "-1e308", "9223372036854775808"] {
            let states = Dictionary(uniqueKeysWithValues: keys.map { ($0, value) })
                .merging(["sensor.charging": "charging"]) { _, incoming in incoming }
            let raw = try reply(states)
            let car = try XCTUnwrap(carFromTemplate(raw))
            XCTAssertNil(car.battery, value)
            XCTAssertNil(car.range, value)
            XCTAssertNil(car.limit, value)
            XCTAssertNil(car.chargerKw, value)
            XCTAssertNil(car.inside, value)
            XCTAssertNil(car.outside, value)
            XCTAssertNil(car.odometer, value)
            XCTAssertNil(car.addedKwh, value)
            XCTAssertNil(car.tires, value)
            XCTAssertNil(car.preciseTires, value)
            XCTAssertNil(car.preciseInside, value)
            XCTAssertNil(car.preciseOutside, value)
            let snapshot = CarFetchResult(cache: CarReadingsCache(current: raw, lastGood: nil,
                checkedAt: Date(timeIntervalSince1970: 1_800_000_000))).snapshot()
            XCTAssertNil(snapshot.battery, value)
            XCTAssertEqual(snapshot.cabin, "—", value)
            XCTAssertEqual(snapshot.outside, "—", value)
            XCTAssertEqual(snapshot.tires, "—", value)
        }
    }

    // A single corrupt pressure should not cause precision-based summary formatting to trap.
    func testOneHugePressureMakesTheAggregateUnknownWhileRawReplyIsRetained() throws {
        let raw = try reply([
            "sensor.battery_level": "57", "sensor.tire_pressure_front_left": "39.5",
            "sensor.tire_pressure_front_right": "1e100", "sensor.tire_pressure_rear_left": "40.25",
            "sensor.tire_pressure_rear_right": "40.75"
        ])
        let car = try XCTUnwrap(carFromTemplate(raw))
        XCTAssertNil(car.tires)
        XCTAssertNil(car.preciseTires)
        let cache = try carReadingsAfterReply(raw, previous: nil, checkedAt: Date())
        XCTAssertEqual(cache.current, raw)
        XCTAssertEqual(CarFetchResult(cache: cache).snapshot().tires, "—")
    }

    // The representability guard must preserve normal decimal precision and existing rounding.
    func testOrdinaryFractionalReadingsKeepPrecisionAndRounding() throws {
        let car = try XCTUnwrap(carFromTemplate(try reply([
            "sensor.battery_level": "57.5", "sensor.battery_range": "175.31", "number.charge_limit": "80",
            "sensor.charger_power": "7.25", "sensor.inside_temperature": "21.5",
            "sensor.outside_temperature": "-2.5", "sensor.odometer": "12345.6",
            "sensor.charge_energy_added": "1.26", "sensor.tire_pressure_front_left": "2.7",
            "sensor.tire_pressure_front_right": "2.8", "sensor.tire_pressure_rear_left": "2.6",
            "sensor.tire_pressure_rear_right": "2.7"
        ])))
        XCTAssertEqual(car.battery, 58)
        XCTAssertEqual(car.range, 175)
        XCTAssertEqual(car.limit, 80)
        XCTAssertEqual(car.chargerKw, 7.25)
        XCTAssertEqual(car.inside, 22)
        XCTAssertEqual(car.outside, -3)
        XCTAssertEqual(car.preciseInside, 21.5)
        XCTAssertEqual(car.preciseOutside, -2.5)
        XCTAssertEqual(car.odometer, 12346)
        XCTAssertEqual(car.addedKwh, 1.3)
        XCTAssertEqual(car.preciseTires, [2.7, 2.8, 2.6, 2.7])
    }

    // Double(Int.max) rounds above the upper bound; comparing against it with <= is unsafe.
    func testRoundedIntBoundaryRejectsRoundedUpperLimitButKeepsRepresentableLowerLimit() throws {
        let rejected = try XCTUnwrap(carFromTemplate(try reply(["sensor.battery_level": "9223372036854775807"])))
        XCTAssertNil(rejected.battery)
        let accepted = try XCTUnwrap(carFromTemplate(try reply(["sensor.battery_level": "-9223372036854775808"])))
        XCTAssertEqual(accepted.battery, Int.min)
    }

    private func reply(_ states: [String: String]) throws -> String {
        let payload: [String: Any] = ["found": true, "prefix": "stargate", "s": states]
        return String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    }
}
