import XCTest
@testable import HearthKit

final class CarReadingsPrimaryTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_800_000_000)

    private func raw(_ states: [String: String], prefix: String? = "stargate") throws -> String {
        var object: [String: Any] = ["found": true, "name": "Long vehicle name", "s": states]
        if let prefix { object["prefix"] = prefix }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func origin(_ status: CarOriginStatus = .readings,
                        prefix: String? = "stargate", historical: Bool = false) -> CarReadingOrigin {
        CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: prefix, status: status, configReady: status != .setup,
            observedAt: observed, displayedObservedAt: observed, attemptedAt: observed,
            historical: historical)
    }

    private func primary(_ states: [String: String], status: CarOriginStatus = .readings,
                         prefix: String? = "stargate", historical: Bool = false,
                         error: String? = nil) throws -> CarReadingsPrimary {
        let cache = CarReadingsCache(current: try raw(states), lastGood: nil, checkedAt: observed)
        return CarDetailedReadings(origin: origin(status, prefix: prefix, historical: historical),
            cache: cache, error: error).attention.primary
    }

    // Prioritizing battery or charging before a confirmed opening would hide a useful warning.
    func testCurrentRawWarningsKeepTheirPriority() throws {
        var states = [
            "sensor.battery_level": "19.8", "binary_sensor.charge_cable": "off",
            "sensor.charging": "charging", "lock.lock": "unlocked",
            "binary_sensor.front_driver_door": "on",
            "binary_sensor.front_passenger_door": "unknown",
            "binary_sensor.tire_pressure_warning_front_left": "on"
        ]
        XCTAssertEqual(try primary(states), .openings)
        states["binary_sensor.front_driver_door"] = "off"
        XCTAssertEqual(try primary(states), .unlocked)
        states["lock.lock"] = "locked"
        XCTAssertEqual(try primary(states), .tireWarning)
        states["binary_sensor.tire_pressure_warning_front_left"] = "off"
        XCTAssertEqual(try primary(states), .lowBattery)
        states["binary_sensor.charge_cable"] = "on"
        XCTAssertEqual(try primary(states), .charging(starting: false))
        states["sensor.charging"] = "starting"
        XCTAssertEqual(try primary(states), .charging(starting: true))
        states["sensor.charging"] = "stopped"
        XCTAssertEqual(try primary(states), .battery(19.8))
    }

    // Rounding 20.4 to 20 must not create the raw <=20 low-battery warning.
    func testBatteryWarningUsesValidatedRawPercentage() throws {
        XCTAssertEqual(try primary(["sensor.battery_level": "20.4",
                                    "binary_sensor.charge_cable": "off"]), .battery(20.4))
        for value in ["unknown", "unavailable", "", "-1", "101", "nan", "inf"] {
            XCTAssertEqual(try primary(["sensor.battery_level": value]), .noReading, value)
        }
    }

    // Missing or unrecognized security values cannot be promoted to a positive assurance.
    func testUnknownSecurityDoesNotInventAnAssurance() throws {
        let states = ["sensor.battery_level": "79.25", "lock.lock": "unknown",
                      "cover.trunk": "opening", "cover.windows": "unavailable",
                      "binary_sensor.tire_pressure_warning_front_left": "unknown"]
        XCTAssertEqual(try primary(states), .battery(79.25))
        XCTAssertEqual(try primary(states.filter { $0.key != "sensor.battery_level" },
                                   status: .noReading), .noReading)
    }

    // An identified current reply can warn about an opening even without a battery reading.
    func testMissingBatteryDoesNotSuppressConfirmedOpening() throws {
        XCTAssertEqual(try primary(["sensor.battery_level": "unknown",
                                    "cover.trunk": "open"], status: .noReading), .openings)
    }

    // An open charge-port cover is a warning only when the cable is explicitly disconnected.
    func testChargePortRequiresConfirmedDisconnectedCable() throws {
        for cable in ["unknown", "on", "unavailable"] {
            XCTAssertEqual(try primary(["sensor.battery_level": "79",
                                        "cover.charge_port_door": "open",
                                        "binary_sensor.charge_cable": cable]), .battery(79))
        }
        XCTAssertEqual(try primary(["cover.charge_port_door": "open",
                                    "binary_sensor.charge_cable": "off"], status: .noReading), .openings)
    }

    // Retained current-cache warnings must not acquire fresh attribution after a failed read.
    func testRetainedAuthenticationFailureKeepsHistoryAndRecovery() throws {
        let states = ["sensor.battery_level": "79", "lock.lock": "unlocked"]
        XCTAssertEqual(try primary(states, status: .history, historical: true),
                       .lastKnown(authenticationRequired: false))
        XCTAssertEqual(try primary(states, status: .failed, error: "Can't reach Home Assistant"),
                       .lastKnown(authenticationRequired: false))
        XCTAssertEqual(try primary(states, status: .authenticationFailure),
                       .lastKnown(authenticationRequired: true))
    }

    // Latest warnings must not be blended into the displayed last-good cohort.
    func testWholeReplyHistoryFallbackRemainsLastKnown() throws {
        let good = try raw(["sensor.battery_level": "84", "lock.lock": "locked"])
        let latest = try raw(["sensor.battery_level": "unknown", "lock.lock": "unlocked"])
        let cache = CarReadingsCache(current: latest, lastGood: good, checkedAt: observed,
            lastGoodCheckedAt: observed.addingTimeInterval(-60))
        let detail = CarDetailedReadings(origin: origin(.history, historical: true), cache: cache)
        XCTAssertEqual(detail.attention.primary, .lastKnown(authenticationRequired: false))
        XCTAssertEqual(detail.cohorts.map(\.attribution), [.historical, .current])
    }

    // A matching display name is never evidence that a raw reply belongs to this vehicle.
    func testMismatchAndUnidentifiedRepliesCannotSupplyBatteryAnswer() throws {
        let cache = CarReadingsCache(current: try raw(["sensor.battery_level": "79"],
            prefix: "different-car"), lastGood: nil, checkedAt: observed)
        XCTAssertEqual(CarDetailedReadings(origin: origin(), cache: cache).attention.primary,
                       .identityMismatch)
        XCTAssertEqual(try primary(["sensor.battery_level": "79"], status: .unidentified,
                                   prefix: nil), .unidentified)
    }

    // Recovery origins must not adopt telemetry from a cache left in memory.
    func testRecoveryStatesRemainExplicit() throws {
        let cache = CarReadingsCache(current: try raw(["sensor.battery_level": "79"]),
            lastGood: nil, checkedAt: observed)
        for (status, expected) in [(CarOriginStatus.setup, CarReadingsPrimary.setup),
                                  (.noCar, .noCar), (.obsolete, .changed),
                                  (.storageUnavailable, .storageUnavailable)] {
            XCTAssertEqual(CarDetailedReadings(origin: origin(status), cache: cache).attention.primary,
                           expected, status.rawValue)
        }
        XCTAssertEqual(CarDetailedReadings(origin: origin(.authenticationFailure), cache: nil)
            .attention.primary, .signIn)
        XCTAssertEqual(CarDetailedReadings(origin: origin(.failed), cache: nil, error: "Offline")
            .attention.primary, .readFailed)
    }

    // The summary must describe the saved raw record, even if a formatted snapshot is different.
    func testEntrySummaryAndTicketBindTheSameRawEnvelope() throws {
        let reply = try raw(["sensor.battery_level": "79.25", "cover.trunk": "open"])
        let cache = CarReadingsCache(current: reply, lastGood: nil, checkedAt: observed)
        let result = CarFetchResult(cache: cache)
        var snapshot = result.snapshot(now: observed)
        snapshot.battery = 12
        snapshot.doorsWarn = false
        let envelope = CarLiveEnvelope(snapshot: snapshot, result: result, origin: origin(),
            requestReply: .success(reply))
        var saved: CarReadingsTicket?
        let entry = bindCarReadingsEntry(envelope, date: observed) { saved = $0 }
        XCTAssertEqual(entry.primary, .openings)
        XCTAssertEqual(entry.snapshot, snapshot)
        XCTAssertEqual(saved?.cache?.current, reply)
        XCTAssertEqual(saved?.entryID, entry.entryID)
        XCTAssertEqual(entry.destination, .ticket(try XCTUnwrap(saved).id))
    }

    // Failing persistence keeps telemetry semantics but never publishes a non-existent ticket.
    func testPersistenceFailurePreservesPrimaryWithoutPublishingTicket() throws {
        let reply = try raw(["sensor.battery_level": "79"])
        let result = CarFetchResult(cache: CarReadingsCache(current: reply, lastGood: nil,
            checkedAt: observed))
        let envelope = CarLiveEnvelope(snapshot: result.snapshot(now: observed), result: result,
            origin: origin(), requestReply: .success(reply))
        let entry = bindCarReadingsEntry(envelope, date: observed) { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(entry.primary, .battery(79))
        XCTAssertEqual(entry.destination, .storageUnavailable)
        XCTAssertEqual(carReadingsURL(for: entry.destination)?.absoluteString,
                       "hearth://car-readings/unavailable")
    }

    // Revoking a stale entry's interactions must not make its failed-save presentation look saved.
    func testDisablingInteractionsPreservesSaveFailureAndChosenReading() {
        let date = observed
        let entry = CarReadingsEntryPayload(entryID: UUID(), date: date, snapshot: .sample,
            destination: .storageUnavailable, primary: .battery(72))
        let inert = entry.disablingInteractions()
        XCTAssertTrue(inert.readingsUnavailable)
        XCTAssertEqual(inert.primary, entry.primary)
        XCTAssertEqual(inert.snapshot, entry.snapshot)
        XCTAssertEqual(inert.entryID, entry.entryID)
        XCTAssertEqual(inert.date, date)
        XCTAssertEqual(inert.destination, .inert)
        XCTAssertNil(carReadingsURL(for: inert.destination))
    }

    // Inert examples require no raw store, while snapshot-only callers default conservatively.
    func testInertSampleHasExplicitPrimaryWithoutFetching() async {
        let entry = await loadCarReadingsEntry(selection: .inert,
            fetchEnvelope: { XCTFail("Inert preview must not fetch"); return .storageUnavailable() },
            persist: { _, _ in XCTFail("Inert preview must not persist") })
        XCTAssertEqual(entry.primary, .battery(72))
        XCTAssertEqual(entry.destination, .inert)
        XCTAssertNil(carReadingsURL(for: entry.destination))
        XCTAssertEqual(CarReadingsEntryPayload(entryID: UUID(), date: observed,
            snapshot: .sample, destination: .inert).primary, .noReading)
    }
}
