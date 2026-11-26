import XCTest
@testable import HearthKit

final class CarSmallPresentationTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ states: [String: String], status: CarOriginStatus = .readings,
                       history: [String: String]? = nil, saveFails: Bool = false) throws -> CarReadingsEntryPayload {
        func raw(_ states: [String: String]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: [
                "found": true, "prefix": "stargate", "name": "Stargate", "s": states,
                "unit": "mi"
            ]), as: UTF8.self)
        }
        let cache = CarReadingsCache(current: try raw(states), lastGood: try history.map(raw),
            checkedAt: observed, lastGoodCheckedAt: history == nil ? nil : observed.addingTimeInterval(-900))
        let result = CarFetchResult(cache: cache)
        let origin = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: "stargate", status: status, configReady: true,
            observedAt: observed, displayedObservedAt: result.displayedObservedAt,
            attemptedAt: observed.addingTimeInterval(60), historical: status == .history)
        return bindCarReadingsEntry(CarLiveEnvelope(snapshot: result.snapshot(now: observed),
            result: result, origin: origin, requestReply: .success(cache.current)),
            date: observed.addingTimeInterval(60)) { _ in
                if saveFails { throw CocoaError(.fileWriteNoPermission) }
            }
    }

    func testWarningsRetainRawPriorityAndDoNotBecomeBatteryAnswers() throws {
        let entry = try entry(["sensor.battery_level": "19.8", "cover.trunk": "open",
            "lock.lock": "unlocked", "sensor.charging": "charging",
            "binary_sensor.charge_cable": "off"])
        let content = carSmallContent(entry)
        XCTAssertEqual(content.criticalTexts, ["Openings"])
        XCTAssertEqual(content.battery, "20%")
        XCTAssertEqual(content.openingDetail, "Trunk")
        XCTAssertEqual(content.tone, .yellow)
        XCTAssertEqual(content.navigationURL, carReadingsURL(for: entry.destination))
    }

    func testRoundedBatteryDoesNotManufactureLowBatteryTone() throws {
        let content = carSmallContent(try entry(["sensor.battery_level": "20.4",
            "binary_sensor.charge_cable": "off"]))
        XCTAssertEqual(content.battery, "20%")
        XCTAssertEqual(content.criticalTexts, [])
        XCTAssertEqual(content.tone, .slate) // Opening states are unreported, not a green assurance.
        XCTAssertTrue(content.openingsUnknown)
    }

    func testHistoricalFallbackUsesItsOwnOpeningAvailabilityAndObservationTime() throws {
        let entry = try entry(["sensor.battery_level": "unknown", "cover.trunk": "closed"],
            status: .history, history: ["sensor.battery_level": "79", "cover.trunk": "open"])
        let content = carSmallContent(entry)
        XCTAssertEqual(content.criticalTexts, ["Last known"])
        XCTAssertEqual(content.battery, "79%")
        XCTAssertEqual(content.tone, .offline)
        XCTAssertNil(content.openingDetail) // Old opening is not a current warning.
        XCTAssertEqual(content.observedAt, observed.addingTimeInterval(-900))
        XCTAssertEqual(entry.smallReading?.openings, ["Trunk"])
        XCTAssertNotEqual(content.observedAt, entry.date)
    }

    func testFreshUnknownOpeningsDoNotBorrowKnownHistory() throws {
        let closed = Dictionary(uniqueKeysWithValues: [
            "binary_sensor.front_driver_door", "binary_sensor.front_passenger_door",
            "binary_sensor.rear_driver_door", "binary_sensor.rear_passenger_door"
        ].map { ($0, "off") } + ["cover.frunk", "cover.trunk", "cover.windows",
                               "cover.charge_port_door"].map { ($0, "closed") })
        let entry = try entry(["sensor.battery_level": "71", "cover.trunk": "unknown"],
            history: closed.merging(["sensor.battery_level": "79"], uniquingKeysWith: { _, new in new }))
        XCTAssertFalse(try XCTUnwrap(entry.smallReading).openingsKnown)
        XCTAssertTrue(carSmallContent(entry).openingsUnknown)
        XCTAssertEqual(carSmallContent(entry).observedAt, observed)
    }

    func testAuthenticationHistoryKeepsBothCriticalLabels() throws {
        let content = carSmallContent(try entry(["sensor.battery_level": "79",
            "lock.lock": "unlocked"], status: .authenticationFailure))
        XCTAssertEqual(content.criticalTexts, ["Last known", "Sign in"])
        XCTAssertEqual(content.tone, .offline)
        XCTAssertEqual(content.battery, "79%")
        XCTAssertEqual(content.statusSymbol, "exclamationmark.circle")
    }

    func testChargingKeepsItsExistingFreshToneAndStartingLabel() throws {
        var states = Dictionary(uniqueKeysWithValues: [
            "binary_sensor.front_driver_door", "binary_sensor.front_passenger_door",
            "binary_sensor.rear_driver_door", "binary_sensor.rear_passenger_door"
        ].map { ($0, "off") } + ["cover.frunk", "cover.trunk", "cover.windows",
                               "cover.charge_port_door"].map { ($0, "closed") })
        states["sensor.battery_level"] = "64"
        states["binary_sensor.charge_cable"] = "on"
        states["sensor.charging"] = "starting"
        let content = carSmallContent(try entry(states))
        XCTAssertEqual(content.criticalTexts, ["Starting"])
        XCTAssertEqual(content.battery, "64%")
        XCTAssertEqual(content.tone, .blue)
        XCTAssertEqual(content.statusSymbol, "bolt")
        XCTAssertFalse(content.openingsUnknown)
    }

    func testInvalidPercentageNeverBecomesZeroOrUsesSnapshotFallback() {
        for value in [-1.0, 101.0, Double.nan, Double.infinity] {
            let payload = CarReadingsEntryPayload(entryID: UUID(), date: observed,
                snapshot: .sample, destination: .inert, primary: .battery(value))
            let content = carSmallContent(payload)
            XCTAssertNil(content.battery)
            XCTAssertEqual(content.criticalTexts, ["No reading"])
            XCTAssertEqual(content.tone, .offline)
        }
    }

    func testWarningDoesNotRoundAnInvalidRawPercentageIntoAValidSupplement() throws {
        for value in ["100.4", "-0.4", "101", "nan", "unknown"] {
            let payload = try entry(["sensor.battery_level": value, "cover.trunk": "open"])
            XCTAssertEqual(carSmallContent(payload).criticalTexts, ["Openings"])
            XCTAssertNil(carSmallContent(payload).battery, value)
        }
    }

    func testUnsavedWarningSurvivesAuthorityRevocation() throws {
        let payload = try entry(["sensor.battery_level": "79", "cover.windows": "open"], saveFails: true)
        let savedFailure = carSmallContent(payload)
        XCTAssertEqual(savedFailure.criticalTexts, ["Openings", "Not saved"])
        XCTAssertEqual(savedFailure.navigationURL?.absoluteString, "hearth://car-readings/unavailable")
        let inert = payload.disablingInteractions()
        XCTAssertEqual(inert.smallReading, payload.smallReading)
        XCTAssertEqual(carSmallContent(inert).criticalTexts, savedFailure.criticalTexts)
        XCTAssertNil(carSmallContent(inert).navigationURL)
        XCTAssertTrue(carSmallAccessibility(carSmallContent(inert)).contains("Example"))
    }

    func testRecoveryCannotAdoptTelemetryFromRetainedCache() throws {
        for status in [CarOriginStatus.setup, .noCar, .obsolete, .storageUnavailable, .unidentified] {
            let payload = try entry(["sensor.battery_level": "79", "cover.trunk": "open"], status: status)
            XCTAssertNil(payload.smallReading, status.rawValue)
            XCTAssertNil(carSmallContent(payload).battery, status.rawValue)
        }
    }
}
