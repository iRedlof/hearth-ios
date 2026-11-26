import XCTest
@testable import HearthKit

final class CarStateTests: XCTestCase {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let loc = Locale(identifier: "en_US")
    var now: Date { parseOffsetDateTime("2026-10-14T09:30:00Z")! }

    // Baseline `s`: asleep at home, locked, unplugged.
    func baselineS() -> [String: String] {
        [
            "sensor.battery_level": "57", "sensor.battery_range": "175.31",
            "sensor.charging": "disconnected", "sensor.charger_power": "0",
            "sensor.time_to_full_charge": "unavailable", "sensor.inside_temperature": "68.9",
            "binary_sensor.status": "off", "binary_sensor.charge_cable": "off",
            "binary_sensor.front_driver_door": "off", "binary_sensor.front_passenger_door": "off",
            "binary_sensor.rear_driver_door": "off", "binary_sensor.rear_passenger_door": "off",
            "binary_sensor.tire_pressure_warning_front_left": "off", "binary_sensor.tire_pressure_warning_front_right": "off",
            "binary_sensor.tire_pressure_warning_rear_left": "off", "binary_sensor.tire_pressure_warning_rear_right": "off",
            "cover.frunk": "closed", "cover.trunk": "closed", "cover.windows": "closed", "cover.charge_port_door": "closed",
            "lock.lock": "locked", "switch.sentry_mode": "off", "device_tracker.location": "home",
            "number.charge_limit": "80",
            "sensor.tire_pressure_front_left": "39.16", "sensor.tire_pressure_front_right": "39.52",
            "sensor.tire_pressure_rear_left": "39.52", "sensor.tire_pressure_rear_right": "40.25",
            "sensor.outside_temperature": "unknown", "sensor.odometer": "unknown",
            "sensor.charge_energy_added": "unknown", "climate.climate": "unknown",
        ]
    }

    func reply(_ overrides: [String: String] = [:], name: String = "Stargate", unit: String = "mi",
               tempUnit: String = "°F", pressureUnit: String = "psi",
               statusSince: String? = "2026-10-14T05:33:23.678473+00:00") -> String {
        var s = baselineS()
        for (k, v) in overrides { s[k] = v }
        var o: [String: Any] = ["found": true, "name": name, "unit": unit, "tempUnit": tempUnit,
                                "pressureUnit": pressureUnit, "s": s]
        o["statusSince"] = statusSince ?? NSNull()
        return String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }

    func car(_ overrides: [String: String] = [:]) -> Car { carFromTemplate(reply(overrides))! }
    func view(_ overrides: [String: String] = [:], stale: Bool = false) -> CarView {
        carView(car(overrides), now: now, zone: zone, locale: loc, stale: stale)
    }

    func test01_noCarIsNone() {
        XCTAssertNil(carFromTemplate(#"{"found": false}"#))
    }

    func test02_asleepHomeLockedUnplugged() {
        let v = view()
        XCTAssertEqual(v.headline, "57% · 175 mi")
        XCTAssertEqual(v.charge, "Not plugged in · limit 80%")
        XCTAssertEqual(v.tone, .calm)
        XCTAssertEqual(v.facts.map(\.text), ["Locked", "All shut", "69° in"])
        XCTAssertEqual(v.asOf, "Asleep since Tue 10:33 PM")
        XCTAssertEqual(v.tires, "Tires 39 · 40 front, 40 · 40 rear psi")
    }

    func test03_chargingHowFastWhenFull() {
        let v = view(["sensor.charging": "charging", "binary_sensor.charge_cable": "on",
                      "sensor.charger_power": "7", "sensor.time_to_full_charge": "2026-10-14T13:10:00+00:00",
                      "cover.charge_port_door": "open", "binary_sensor.status": "on"])
        XCTAssertEqual(v.charge, "Charging · 7 kW · full at 6:10 AM")
        XCTAssertEqual(v.facts[1].text, "All shut")
        XCTAssertEqual(v.asOf, "Awake")
    }

    func test04_chargedAndPlugged() {
        XCTAssertEqual(view(["sensor.charging": "complete", "binary_sensor.charge_cable": "on"]).charge, "Charged to 80%")
        XCTAssertEqual(view(["sensor.charging": "stopped", "binary_sensor.charge_cable": "on"]).charge, "Plugged in, not charging · limit 80%")
    }

    func test05_unlockedOpenAmberAwayRed() {
        let a = view(["cover.frunk": "open", "binary_sensor.rear_driver_door": "on"])
        XCTAssertEqual(a.tone, .warn)
        XCTAssertEqual(a.facts[1].text, "Door, Frunk open")
        XCTAssertTrue(a.facts[1].bad)
        XCTAssertEqual(view(["lock.lock": "unlocked"]).tone, .warn)
        let c = view(["lock.lock": "unlocked", "device_tracker.location": "not_home"])
        XCTAssertEqual(c.tone, .alert)
        XCTAssertEqual(c.facts.map(\.text), ["Unlocked", "All shut", "69° in"])
    }

    func test06_lowUnpluggedAmber_tireWarningFact() {
        XCTAssertEqual(view(["sensor.battery_level": "18"]).tone, .warn)
        let b = view(["binary_sensor.tire_pressure_warning_rear_left": "on", "switch.sentry_mode": "on"])
        XCTAssertEqual(b.facts.map(\.text), ["Locked", "All shut", "Check tires", "69° in"])
        XCTAssertEqual(b.tone, .warn)
    }

    func test07_lowBatteryWarnsOnlyWhenKnownUnplugged() {
        XCTAssertEqual(view(["sensor.battery_level": "18", "binary_sensor.charge_cable": "unavailable"]).tone, .calm)
        XCTAssertEqual(view(["sensor.battery_level": "18"]).tone, .warn)
        XCTAssertEqual(view(["sensor.battery_level": "18", "binary_sensor.charge_cable": "on"]).tone, .calm)
    }

    func test08_openChargePortFlaggedOnlyIfKnownUnplugged() {
        XCTAssertEqual(car(["cover.charge_port_door": "open", "binary_sensor.charge_cable": "unavailable"]).open, [])
        let disconnected = car(["cover.charge_port_door": "open", "binary_sensor.charge_cable": "off"])
        XCTAssertEqual(disconnected.open, ["Charge port"])
        XCTAssertTrue(disconnected.openKnown)
        XCTAssertEqual(carView(disconnected, now: now, zone: zone, locale: loc).facts[1].text, "Charge port open")
        let snapshot = carSnapshot(disconnected, now: now, stale: false, checkedAt: now, zone: zone, locale: loc)
        XCTAssertEqual(snapshot.doors, "Charge port open")
        XCTAssertTrue(snapshot.doorsWarn)
    }

    func test09_shortChargeLineParallel() {
        func cs(_ ov: [String: String], _ p: Bool) -> String { carChargeShort(car(ov), withPower: p, locale: loc) }
        XCTAssertEqual(cs(["sensor.charging": "complete", "binary_sensor.charge_cable": "on"], true), "Charged")
        XCTAssertEqual(cs(["sensor.charging": "complete", "binary_sensor.charge_cable": "on"], false), "Charged")
        XCTAssertEqual(cs(["sensor.charging": "charging", "sensor.charger_power": "7", "binary_sensor.charge_cable": "on"], true), "Charging · 7 kW")
        XCTAssertEqual(cs(["sensor.charging": "charging", "sensor.charger_power": "0", "binary_sensor.charge_cable": "on"], true), "Charging")
        XCTAssertEqual(cs(["sensor.charging": "charging", "sensor.charger_power": "7", "binary_sensor.charge_cable": "on"], false), "Charging")
        XCTAssertEqual(cs(["sensor.charging": "disconnected", "binary_sensor.charge_cable": "off"], true), "Unplugged")
        XCTAssertEqual(cs(["sensor.charging": "disconnected", "binary_sensor.charge_cable": "unavailable"], true), "Plug status —")
    }

    func test10_unknownReadingsLeftOut() {
        let v = view(["sensor.battery_range": "unavailable", "sensor.inside_temperature": "unknown",
                      "lock.lock": "unavailable"], stale: false)
        // statusSince null for this one
        let json = reply(["sensor.battery_range": "unavailable", "sensor.inside_temperature": "unknown", "lock.lock": "unavailable"], statusSince: nil)
        let v2 = carView(carFromTemplate(json)!, now: now, zone: zone, locale: loc)
        XCTAssertEqual(v.headline, "57%")
        XCTAssertEqual(v2.facts.map(\.text), ["All shut"])
        XCTAssertEqual(v2.asOf, "Asleep")
        XCTAssertNil(car(["sensor.tire_pressure_rear_left": "unknown"]).tires)
    }

    func test11_sublineRangeWhereOrCharging() {
        XCTAssertEqual(view().subline, "175 mi · Home")
        XCTAssertEqual(view(["sensor.charging": "charging", "binary_sensor.charge_cable": "on",
                             "sensor.charger_power": "7", "sensor.time_to_full_charge": "2026-10-14T13:10:00+00:00"]).subline,
                       "Charging 7 kW · full by 6:10 AM")
        XCTAssertEqual(view(["device_tracker.location": "not_home"]).subline, "175 mi · Away")
    }

    func test12_dashboardReadings() {
        let c = car(["sensor.outside_temperature": "55.4", "sensor.odometer": "20961.011817",
                     "sensor.charge_energy_added": "20.82", "climate.climate": "off", "switch.sentry_mode": "on"])
        XCTAssertEqual(c.outside, 55)
        XCTAssertEqual(c.odometer, 20961)
        XCTAssertEqual(c.addedKwh!, 20.8, accuracy: 0.001)
        XCTAssertEqual(c.climateOn, false)
        XCTAssertEqual(c.tires, [39, 40, 40, 40])
        let v = carView(c, now: now, zone: zone, locale: loc)
        XCTAssertEqual(v.facts.last?.text, "69° in · 55° out")
        XCTAssertTrue(v.sentry)
    }

    func test13_designFollowsSize() {
        XCTAssertEqual(carLayout(272, 200, 1), .ring)
        XCTAssertEqual(carLayout(352, 180, 1), .hero)
        XCTAssertEqual(carLayout(352, 290, 1), .hero)
        XCTAssertEqual(carLayout(315, 343, 1.1), .dashboard)
        XCTAssertEqual(carLayout(352, 340, 1.3), .hero)
    }

    func test14_panelRowsByHeight() {
        XCTAssertEqual(carPanelRows(60, 1), 0)
        XCTAssertEqual(carPanelRows(90, 1), 1)
        XCTAssertEqual(carPanelRows(170, 1), 2)
        XCTAssertEqual(carPanelRows(170, 1.3), 1)
    }

    func test15_keepsLastGoodStale() {
        let good = car()
        let empty = car(["sensor.battery_level": "unknown", "sensor.battery_range": "unknown",
                         "lock.lock": "unknown", "binary_sensor.status": "unknown"])
        XCTAssertEqual(carToShow(empty, good), CarShown(car: good, stale: true))
        XCTAssertEqual(carToShow(good, empty), CarShown(car: good, stale: false))
        XCTAssertEqual(carToShow(empty, nil), CarShown(car: empty, stale: false))
        XCTAssertNil(carToShow(nil, good))
    }

    func test16_oldReadingsSaySo() {
        XCTAssertEqual(view(stale: true).asOf, "No new readings from the car · these are from Tue 10:33 PM")
    }

    func test17_openPortWithUnknownCableDoesNotClaimAllShut() throws {
        let cableStates: [String?] = ["unknown", "unavailable", nil, "connecting"]
        for cable in cableStates {
            var states = baselineS()
            states["cover.charge_port_door"] = "open"
            states["binary_sensor.charge_cable"] = cable
            let payload: [String: Any] = ["found": true, "name": "Stargate", "unit": "mi", "s": states]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let parsed = try XCTUnwrap(carFromTemplate(String(decoding: data, as: UTF8.self)))
            let context = cable ?? "missing cable"
            XCTAssertFalse(parsed.pluggedKnown, context)
            XCTAssertEqual(parsed.open, [], context)
            XCTAssertFalse(parsed.openKnown, context)
            let displayed = carView(parsed, now: now, zone: zone, locale: loc)
            XCTAssertEqual(displayed.facts[1].text, "Openings unknown", context)
            XCTAssertTrue(displayed.charge.hasPrefix("Plug status unknown"), context)
            let snapshot = carSnapshot(parsed, now: now, stale: false, checkedAt: now, zone: zone, locale: loc)
            XCTAssertEqual(snapshot.doors, "—", context)
            XCTAssertFalse(snapshot.doorsWarn, context)
        }
    }

    func test18_closedPortStaysKnownWithUnknownCable() {
        let parsed = car(["binary_sensor.charge_cable": "unknown"])
        XCTAssertFalse(parsed.pluggedKnown)
        XCTAssertEqual(parsed.open, [])
        XCTAssertTrue(parsed.openKnown)
        let displayed = carView(parsed, now: now, zone: zone, locale: loc)
        XCTAssertEqual(displayed.facts[1].text, "All shut")
        XCTAssertTrue(displayed.charge.hasPrefix("Plug status unknown"))
        let snapshot = carSnapshot(parsed, now: now, stale: false, checkedAt: now, zone: zone, locale: loc)
        XCTAssertEqual(snapshot.doors, "All shut")
        XCTAssertFalse(snapshot.doorsWarn)
    }

    func test19_reportedTrunkRemainsWarningWithAmbiguousPort() {
        let parsed = car(["cover.trunk": "open", "cover.charge_port_door": "open",
                          "binary_sensor.charge_cable": "unknown"])
        XCTAssertEqual(parsed.open, ["Trunk"])
        XCTAssertFalse(parsed.openKnown)
        let displayed = carView(parsed, now: now, zone: zone, locale: loc)
        XCTAssertEqual(displayed.facts[1].text, "Trunk open")
        XCTAssertTrue(displayed.facts[1].bad)
        XCTAssertEqual(displayed.tone, .warn)
        let snapshot = carSnapshot(parsed, now: now, stale: false, checkedAt: now, zone: zone, locale: loc)
        XCTAssertEqual(snapshot.doors, "Trunk open")
        XCTAssertTrue(snapshot.doorsWarn)
    }
}
