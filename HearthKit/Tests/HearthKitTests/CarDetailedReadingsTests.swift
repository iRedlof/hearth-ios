import XCTest
@testable import HearthKit

final class CarDetailedReadingsTests: XCTestCase {
    private let checked = Date(timeIntervalSince1970: 1_800_000_000)
    private let zone = TimeZone(secondsFromGMT: 0)!
    private let locale = Locale(identifier: "en_US")

    private var allStates: [String: String] {
        [
            "sensor.battery_level": "79.25", "sensor.battery_range": "221.75",
            "sensor.charging": "charging", "sensor.charger_power": "7.25",
            "sensor.time_to_full_charge": "2027-01-15T09:00:00Z",
            "sensor.inside_temperature": "21.35", "binary_sensor.status": "on",
            "binary_sensor.charge_cable": "on", "binary_sensor.front_driver_door": "off",
            "binary_sensor.front_passenger_door": "on", "binary_sensor.rear_driver_door": "off",
            "binary_sensor.rear_passenger_door": "off",
            "binary_sensor.tire_pressure_warning_front_left": "off",
            "binary_sensor.tire_pressure_warning_front_right": "on",
            "binary_sensor.tire_pressure_warning_rear_left": "off",
            "binary_sensor.tire_pressure_warning_rear_right": "unknown",
            "cover.frunk": "closed", "cover.trunk": "opening", "cover.windows": "closed",
            "cover.charge_port_door": "open", "lock.lock": "locked",
            "switch.sentry_mode": "unknown", "device_tracker.location": "home",
            "number.charge_limit": "85", "sensor.tire_pressure_front_left": "41.25",
            "sensor.tire_pressure_front_right": "42.35", "sensor.tire_pressure_rear_left": "unavailable",
            "sensor.tire_pressure_rear_right": "40.95", "sensor.outside_temperature": "8.65",
            "sensor.odometer": "12876.35", "sensor.charge_energy_added": "3.45",
            "climate.climate": "heat_cool"
        ]
    }

    private func reply(_ states: [String: String], prefix: String? = "stargate",
                       name: String = "Stargate premium", attributes: [String: Any] = [:]) throws -> String {
        var object: [String: Any] = [
            "found": true, "name": name, "unit": "mi", "tempUnit": "°C",
            "pressureUnit": "psi", "statusSince": "2027-01-15T07:00:00Z", "s": states
        ]
        if let prefix { object["prefix"] = prefix }
        for (key, value) in attributes { object[key] = value }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private func origin(_ status: CarOriginStatus = .readings, prefix: String? = "stargate",
                        displayed: Date? = nil, historical: Bool = false) -> CarReadingOrigin {
        CarReadingOrigin(requestScope: "captured-scope", readRevision: "captured-scope",
            vehiclePrefix: prefix, status: status, configReady: status != .setup,
            observedAt: checked, displayedObservedAt: displayed ?? checked,
            attemptedAt: checked.addingTimeInterval(30), historical: historical)
    }

    private func details(_ cache: CarReadingsCache?, status: CarOriginStatus = .readings,
                         prefix: String? = "stargate", error: String? = nil,
                         historical: Bool = false, displayed: Date? = nil,
                         now: Date? = nil) -> CarDetailedReadings {
        CarDetailedReadings(origin: origin(status, prefix: prefix, displayed: displayed, historical: historical),
            cache: cache, error: error, setup: status == .setup, now: now ?? checked,
            zone: zone, locale: locale)
    }

    private func row(_ key: String, in model: CarDetailedReadings, cohort: Int = 0) throws -> CarDetailedReadingRow {
        let value = model.cohorts[safe: cohort]?.sections.flatMap(\.rows).first { $0.id == key }
        return try XCTUnwrap(value, "Expected reachable raw reading \(key)")
    }

    private func cohort(_ index: Int, in model: CarDetailedReadings) throws -> CarDetailedReadingCohort {
        try XCTUnwrap(model.cohorts[safe: index], "Expected attributed cohort \(index)")
    }

    // Dropping any template field, or collapsing distinct doors/wheels, loses a required reading.
    func testCompleteReplyPreservesAllThirtyTwoFieldsAndPrecision() throws {
        let model = details(CarReadingsCache(current: try reply(allStates), lastGood: nil, checkedAt: checked))
        XCTAssertEqual(model.title, "Stargate premium")
        XCTAssertEqual(model.cohorts.count, 1)
        XCTAssertEqual(try cohort(0, in: model).attribution, .current)
        let rows = try cohort(0, in: model).sections.flatMap(\.rows)
        XCTAssertEqual(rows.count, 32)
        XCTAssertEqual(Set(rows.map(\.id)), Set(allStates.keys))
        for (key, raw) in allStates { XCTAssertEqual(try row(key, in: model).rawState, raw) }
        XCTAssertEqual(try row("sensor.battery_level", in: model).value, "79.25%")
        XCTAssertEqual(try row("sensor.battery_range", in: model).value, "221.75 mi")
        XCTAssertEqual(try row("sensor.inside_temperature", in: model).value, "21.35 °C")
        XCTAssertEqual(try row("binary_sensor.front_passenger_door", in: model).value, "Open")
        XCTAssertEqual(try row("binary_sensor.front_driver_door", in: model).value, "Closed")
        XCTAssertEqual(try row("cover.trunk", in: model).value, "Opening")
        XCTAssertEqual(try row("cover.charge_port_door", in: model).value, "Open")
    }

    // Partial tire data must survive even when Car.preciseTires would be nil.
    func testPartialWheelsAndUnconfirmedWarningsRemainIndividual() throws {
        let model = details(CarReadingsCache(current: try reply(allStates), lastGood: nil, checkedAt: checked))
        XCTAssertEqual(try row("sensor.tire_pressure_front_left", in: model).value, "41.25 psi")
        XCTAssertEqual(try row("sensor.tire_pressure_front_right", in: model).value, "42.35 · Unit unavailable")
        XCTAssertEqual(try row("sensor.tire_pressure_rear_left", in: model).availability, .unavailable)
        XCTAssertEqual(try row("sensor.tire_pressure_rear_right", in: model).rawState, "40.95")
        XCTAssertEqual(try row("binary_sensor.tire_pressure_warning_front_right", in: model).value, "Warning")
        XCTAssertEqual(try row("binary_sensor.tire_pressure_warning_rear_right", in: model).value, "Unknown")
        XCTAssertEqual(try row("switch.sentry_mode", in: model).value, "Unknown")
    }

    // Cabin/FL/range attributes do not authorize units on other measurements.
    func testAbsentPerFieldUnitsAreExplicitAndKnownUnitsAreNotBorrowed() throws {
        let model = details(CarReadingsCache(current: try reply(allStates), lastGood: nil, checkedAt: checked))
        for key in ["sensor.outside_temperature", "sensor.odometer", "sensor.charger_power",
                    "sensor.charge_energy_added", "sensor.tire_pressure_front_right"] {
            XCTAssertTrue(try row(key, in: model).unitUnavailable, key)
            XCTAssertNil(try row(key, in: model).unit, key)
        }
        XCTAssertFalse(try row("sensor.battery_range", in: model).unitUnavailable)
        XCTAssertEqual(try row("sensor.battery_range", in: model).unit, "mi")
    }

    // A coherent reply can supply new per-entity units without assuming uniform wheel or temperature units.
    func testExplicitPerFieldUnitAttributesExtendTheLegacyContract() throws {
        let raw = try reply(allStates, attributes: [
            "units": ["sensor.outside_temperature": "°F", "sensor.tire_pressure_front_right": "bar",
                      "sensor.odometer": "km", "sensor.charger_power": "kW", "sensor.charge_energy_added": "kWh"]
        ])
        let model = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked))
        XCTAssertEqual(try row("sensor.outside_temperature", in: model).value, "8.65 °F")
        XCTAssertEqual(try row("sensor.tire_pressure_front_right", in: model).value, "42.35 bar")
        XCTAssertEqual(try row("sensor.odometer", in: model).value, "12876.35 km")
        XCTAssertEqual(try row("sensor.charger_power", in: model).value, "7.25 kW")
        XCTAssertEqual(try row("sensor.charge_energy_added", in: model).value, "3.45 kWh")
    }

    // Boolean defaults must not turn unknown/missing/transitional states into reassuring claims.
    func testUnknownUnavailableAbsentEmptyAndUnrecognizedRemainDistinct() throws {
        let raw = try reply([
            "sensor.battery_level": "79", "binary_sensor.status": "calibrating",
            "lock.lock": "unavailable", "switch.sentry_mode": "unknown",
            "cover.frunk": "", "binary_sensor.charge_cable": "none", "climate.climate": "mystery_mode"
        ])
        let model = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked))
        XCTAssertEqual(try row("switch.sentry_mode", in: model).availability, .unknown)
        XCTAssertEqual(try row("lock.lock", in: model).availability, .unavailable)
        XCTAssertEqual(try row("cover.trunk", in: model).availability, .notReported)
        XCTAssertNil(try row("cover.trunk", in: model).rawState)
        XCTAssertEqual(try row("cover.frunk", in: model).rawState, "")
        XCTAssertEqual(try row("cover.frunk", in: model).availability, .notReported)
        XCTAssertEqual(try row("binary_sensor.charge_cable", in: model).availability, .notReported)
        XCTAssertEqual(try row("binary_sensor.status", in: model).availability, .unrecognized)
        XCTAssertTrue(try row("binary_sensor.status", in: model).value.contains("calibrating"))
        XCTAssertEqual(try row("climate.climate", in: model).availability, .unrecognized)
        XCTAssertFalse(model.attention.title.contains("Asleep"))
    }

    // Whole-car fallback cannot silently attach fresh fields/time to an old displayed cohort.
    func testHistoryAndLatestReplyAreSeparateAttributedCohorts() throws {
        let oldDate = checked.addingTimeInterval(-3_600)
        let good = try reply(["sensor.battery_level": "84", "lock.lock": "locked", "switch.sentry_mode": "off"])
        let latest = try reply(["sensor.battery_level": "unknown", "lock.lock": "unlocked", "switch.sentry_mode": "on"])
        let cache = CarReadingsCache(current: latest, lastGood: good, checkedAt: checked, lastGoodCheckedAt: oldDate)
        let model = details(cache, status: .history, historical: true, displayed: oldDate)
        XCTAssertEqual(model.cohorts.count, 2)
        XCTAssertEqual(try cohort(0, in: model).attribution, .historical)
        XCTAssertEqual(try cohort(0, in: model).observedAt, oldDate)
        XCTAssertEqual(try row("lock.lock", in: model).value, "Locked")
        XCTAssertEqual(try cohort(1, in: model).attribution, .current)
        XCTAssertEqual(try cohort(1, in: model).observedAt, checked)
        XCTAssertEqual(try row("lock.lock", in: model, cohort: 1).value, "Unlocked")
        XCTAssertEqual(try row("sensor.battery_level", in: model, cohort: 1).availability, .unknown)
        XCTAssertEqual(model.attention.title, "Last known")
    }

    // A failed attempt makes both retained cohorts historical; it does not refresh prior lock/Sentry/ETA.
    func testTwoCohortFailureMarksLatestSuccessfulReplyRetainedWithoutRestampingIt() throws {
        let oldDate = checked.addingTimeInterval(-3_600)
        let good = try reply(["sensor.battery_level": "84", "lock.lock": "locked"])
        let latest = try reply(["sensor.battery_level": "unknown", "lock.lock": "unlocked",
                                "switch.sentry_mode": "on", "sensor.time_to_full_charge": "2027-01-15T09:00:00Z"])
        let cache = CarReadingsCache(current: latest, lastGood: good, checkedAt: checked, lastGoodCheckedAt: oldDate)
        for (status, error) in [(CarOriginStatus.failed, "Can't reach Home Assistant" as String?),
                                (.authenticationFailure, nil), (.history, "Refresh interrupted")] {
            let model = details(cache, status: status, error: error, historical: true, displayed: oldDate)
            XCTAssertEqual(try cohort(0, in: model).attribution, .historical)
            XCTAssertEqual(try cohort(0, in: model).observedAt, oldDate)
            XCTAssertEqual(try cohort(1, in: model).attribution, .historical)
            XCTAssertEqual(try cohort(1, in: model).observedAt, checked)
            XCTAssertTrue(try cohort(1, in: model).title.lowercased().contains("retained"))
            XCTAssertTrue(try row("sensor.time_to_full_charge", in: model, cohort: 1).note?.contains("historical") == true)
            XCTAssertEqual(try row("lock.lock", in: model, cohort: 1).value, "Unlocked")
        }
    }

    // Legacy history has no provable sampling date; cache check and completion are separate metadata.
    func testLegacyHistoryDoesNotRestampTelemetryWithCurrentCheckTime() throws {
        let good = try reply(["sensor.battery_level": "84"])
        let latest = try reply(["sensor.battery_level": "unknown"])
        let cache = CarReadingsCache(current: latest, lastGood: good, checkedAt: checked)
        let model = details(cache, status: .history, historical: true)
        XCTAssertNil(try cohort(0, in: model).observedAt)
        XCTAssertTrue(try cohort(0, in: model).sourceRows.contains { $0.id == "observedAt" && $0.value == "Reading time unavailable" })
        XCTAssertEqual(model.sourceRows.first { $0.id == "attemptedAt" }?.date, checked.addingTimeInterval(30))
        XCTAssertEqual(model.sourceRows.first { $0.id == "checkedAt" }?.date, checked)
    }

    // A same friendly name cannot authorize old telemetry from another integration prefix.
    func testDifferentVehicleHistoryIsNeverBorrowed() throws {
        let current = try reply(["sensor.battery_level": "unknown"], prefix: "new-car", name: "Same name")
        let previous = try reply(["sensor.battery_level": "84"], prefix: "old-car", name: "Same name")
        let model = details(CarReadingsCache(current: current, lastGood: previous, checkedAt: checked),
                            status: .noReading, prefix: "new-car")
        XCTAssertEqual(model.cohorts.count, 1)
        XCTAssertEqual(try cohort(0, in: model).vehiclePrefix, "new-car")
        XCTAssertEqual(try row("sensor.battery_level", in: model).availability, .unknown)
        XCTAssertEqual(model.attention.title, "No battery reading")
    }

    // Detail validity must not change which raw cohort the actual compact widget displayed.
    func testInvalidPercentageUsesTheActualDisplayedCohortInsteadOfChoosingDifferentHistory() throws {
        let previous = try reply(["sensor.battery_level": "84"])
        for battery in ["-1", "101"] {
            let latest = try reply(["sensor.battery_level": battery])
            let cache = CarReadingsCache(current: latest, lastGood: previous, checkedAt: checked,
                lastGoodCheckedAt: checked.addingTimeInterval(-3_600))
            let model = details(cache)
            XCTAssertEqual(model.cohorts.count, 1)
            XCTAssertEqual(try cohort(0, in: model).attribution, .current)
            XCTAssertEqual(try cohort(0, in: model).observedAt, checked)
            XCTAssertEqual(try row("sensor.battery_level", in: model).rawState, battery)
            XCTAssertEqual(try row("sensor.battery_level", in: model).availability, .unrecognized)
        }
    }

    // An origin/cache target mismatch must not present replacement telemetry as the bound car.
    func testMismatchedOriginRejectsAllCacheCohorts() throws {
        let raw = try reply(allStates, prefix: "replacement-car")
        let model = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked))
        XCTAssertTrue(model.cohorts.isEmpty)
        XCTAssertEqual(model.attention.title, "Reading identity mismatch")
    }

    // Unknown prefix may expose a plainly unattributed reply, never history or confirmed warning headline.
    func testUnidentifiedReplyDoesNotBorrowHistoryOrRaiseAttributedSecurityWarning() throws {
        let latest = try reply(["sensor.battery_level": "79", "lock.lock": "unlocked"], prefix: nil)
        let previous = try reply(allStates)
        let model = details(CarReadingsCache(current: latest, lastGood: previous, checkedAt: checked),
                            status: .unidentified, prefix: nil)
        XCTAssertEqual(model.cohorts.count, 1)
        XCTAssertEqual(try cohort(0, in: model).attribution, .unidentified)
        XCTAssertNil(try cohort(0, in: model).vehiclePrefix)
        XCTAssertEqual(model.attention.title, "Car could not be identified")
    }

    // The awake transition belongs to that sensor, not to every reading's age.
    func testStatusTransitionDateStaysDistinctFromResponseObservation() throws {
        let model = details(CarReadingsCache(current: try reply(allStates), lastGood: nil, checkedAt: checked))
        let transition = try XCTUnwrap(cohort(0, in: model).sourceRows.first { $0.id == "statusSince" })
        XCTAssertEqual(transition.date, Date(timeIntervalSince1970: 1_799_996_400))
        XCTAssertNotEqual(transition.date, try cohort(0, in: model).observedAt)
        XCTAssertTrue(transition.label.contains("Awake"))
    }

    // A failed attempt thirty seconds after a successful reply must not display an identical check time.
    func testSourceTimesRetainSecondsAndTheInjectedCalendarDay() throws {
        let raw = try reply(allStates)
        let cache = CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked)
        let model = details(cache)
        let replyTime = try XCTUnwrap(model.sourceRows.first { $0.id == "checkedAt" })
        let attemptTime = try XCTUnwrap(model.sourceRows.first { $0.id == "attemptedAt" })
        XCTAssertNotEqual(replyTime.value, attemptTime.value)
        XCTAssertTrue(attemptTime.value.contains("8:00:30"))
        let west = CarDetailedReadings(origin: origin(), cache: cache, now: checked,
            zone: TimeZone(secondsFromGMT: -12 * 3_600)!, locale: locale)
        XCTAssertTrue(try XCTUnwrap(west.sourceRows.first { $0.id == "checkedAt" }).value.contains("Jan 14, 2027"))
    }

    // Past/historical ETAs are records rather than a renewed “Full by” promise.
    func testExpiredAndHistoricalETAStayRecordedDates() throws {
        let raw = try reply(allStates)
        let now = Date(timeIntervalSince1970: 1_800_010_800)
        let current = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked), now: now)
        let eta = try row("sensor.time_to_full_charge", in: current)
        XCTAssertTrue(eta.note?.contains("passed") == true)
        XCTAssertFalse(eta.value.contains("Full by"))
        XCTAssertEqual(eta.rawState, "2027-01-15T09:00:00Z")
        let history = details(CarReadingsCache(current: raw, lastGood: raw, checkedAt: checked),
                              status: .failed, error: "Can't reach Home Assistant", historical: true)
        XCTAssertTrue(try row("sensor.time_to_full_charge", in: history).note?.contains("historical") == true)
    }

    // The complete failure belongs beside the retained reading; it must not truncate or relabel it fresh.
    func testFailurePreservesFullErrorAndRetainedObservation() throws {
        let raw = try reply(allStates)
        let failure = "Can't reach Home Assistant · The complete diagnostic includes a second sentence and actionable context."
        let model = details(CarReadingsCache(current: raw, lastGood: raw, checkedAt: checked),
                            status: .failed, error: failure, historical: true)
        XCTAssertEqual(model.error, failure)
        XCTAssertEqual(model.cohorts.count, 1)
        XCTAssertEqual(try cohort(0, in: model).attribution, .historical)
        XCTAssertEqual(try cohort(0, in: model).observedAt, checked)
        XCTAssertEqual(model.attention.title, "Last known")
    }

    // The failure origin alone prevents fresh assurances even if its optional error text is absent.
    func testFailureOriginWithoutErrorTextKeepsRetainedTelemetryHistorical() throws {
        let raw = try reply(allStates)
        for status: CarOriginStatus in [.failed, .authenticationFailure] {
            let model = details(CarReadingsCache(current: raw, lastGood: raw, checkedAt: checked), status: status)
            XCTAssertEqual(try cohort(0, in: model).attribution, .historical)
            XCTAssertEqual(model.attention.title, "Last known")
        }
    }

    // Fresh opening warnings outrank charging/battery; retained history never becomes a current warning.
    func testFreshAttentionPrioritizesRealOpeningsAndRetainsPluggedChargePortReading() throws {
        let model = details(CarReadingsCache(current: try reply(allStates), lastGood: nil, checkedAt: checked))
        XCTAssertEqual(model.attention.title, "Openings reported")
        XCTAssertTrue(model.attention.message?.contains("Front passenger door") == true)
        XCTAssertFalse(model.attention.message?.contains("Charge port") == true)
        XCTAssertEqual(try row("cover.charge_port_door", in: model).value, "Open")
    }

    // A normal open charge-port while plugged in remains a reading, not a warning displacing charging.
    func testChargePortAttentionRequiresConfirmedDisconnectedCable() throws {
        for (cable, expected) in [("on", "Charging"), ("unknown", "Charging"), ("off", "Openings reported")] {
            let raw = try reply(["sensor.battery_level": "79", "sensor.charging": "charging",
                                 "cover.charge_port_door": "open", "binary_sensor.charge_cable": cable])
            let model = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked))
            XCTAssertEqual(model.attention.title, expected)
            XCTAssertEqual(try row("cover.charge_port_door", in: model).value, "Open")
        }
    }

    // Reuse the established warning contract: ≤20% is a charge-me warning only when unplugged is known.
    func testLowBatteryAttentionPreservesKnownCableStateAndTwentyPercentBoundary() throws {
        let inputs: [(String, String, String, String)] = [
            ("20", "off", "stopped", "Low battery"),
            ("18", "on", "charging", "Charging"),
            ("18", "unknown", "charging", "Charging"),
            ("18", "unavailable", "stopped", "18% battery")
        ]
        for (battery, cable, charging, headline) in inputs {
            let raw = try reply(["sensor.battery_level": battery, "binary_sensor.charge_cable": cable,
                                 "sensor.charging": charging])
            let model = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked))
            XCTAssertEqual(model.attention.title, headline)
        }
    }

    // Missing or bad numeric values cannot create “0” or a fabricated asleep/clear claim.
    func testNonFiniteAndUnrecognizedNumbersRemainUnrecognized() throws {
        let raw = try reply(["sensor.battery_level": "NaN", "sensor.battery_range": "Infinity",
                             "sensor.inside_temperature": "broken"])
        let model = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked), status: .noReading)
        XCTAssertEqual(try row("sensor.battery_level", in: model).availability, .unrecognized)
        XCTAssertEqual(try row("sensor.battery_range", in: model).availability, .unrecognized)
        XCTAssertEqual(try row("sensor.inside_temperature", in: model).availability, .unrecognized)
    }

    // Invalid percentages must remain visible as invalid readings, not a low-battery warning or charge goal.
    func testOutOfRangePercentagesDoNotCreateBatteryAssurances() throws {
        for rawBattery in ["-1", "101", "1e100"] {
            let raw = try reply(["sensor.battery_level": rawBattery, "number.charge_limit": "101"])
            let model = details(CarReadingsCache(current: raw, lastGood: nil, checkedAt: checked), status: .noReading)
            XCTAssertEqual(try row("sensor.battery_level", in: model).availability, .unrecognized)
            XCTAssertEqual(try row("number.charge_limit", in: model).availability, .unrecognized)
            XCTAssertEqual(model.attention.title, "No battery reading")
            XCTAssertEqual(try row("sensor.battery_level", in: model).rawState, rawBattery)
        }
    }

    // Setup/no-car/storage and obsolete origins must not surface sample/old telemetry as a usable reading.
    func testRecoveryStatesNeverPresentStaleCacheAsCurrentData() throws {
        let raw = try reply(allStates)
        let cache = CarReadingsCache(current: raw, lastGood: raw, checkedAt: checked)
        let cases: [(CarOriginStatus, String)] = [
            (.setup, "Connect Home Assistant"), (.noCar, "No car found"),
            (.storageUnavailable, "Readings storage unavailable"), (.obsolete, "Widget reading changed")
        ]
        for (status, title) in cases {
            let model = details(cache, status: status)
            XCTAssertTrue(model.cohorts.isEmpty, "\(status)")
            XCTAssertEqual(model.attention.title, title)
        }
    }

    // Authentication without telemetry still supplies the real recovery state, not generic “No reading.”
    func testAuthenticationFailureWithoutCacheHasTruthfulRecovery() {
        let model = details(nil, status: .authenticationFailure, error: "HTTP 401 · Sign in again")
        XCTAssertTrue(model.cohorts.isEmpty)
        XCTAssertEqual(model.attention.title, "Sign in again")
        XCTAssertEqual(model.error, "HTTP 401 · Sign in again")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
