import XCTest
@testable import HearthKit

final class ThermostatSmallPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let locale = Locale(identifier: "en_US")
    private func envelope(mode: String = "heat_cool", action: String? = nil, room: Double? = -2.56,
                          unit: String? = "°C", context: Bool = true,
                          failures: [String: HaStateFailure] = [:], operation: ClimateOperation? = nil,
                          recovery: ThermostatRecovery = .none, authenticated: Bool = true,
                          modes: [String] = ["heat_cool", "heat", "cool", "off"]) throws -> ThermostatLiveEnvelope {
        var attributes: [String: Any] = ["friendly_name": "Hallway", "temperature": 20.125,
            "target_temp_low": 7.126, "target_temp_high": 12.764, "target_temp_step": 0,
            "hvac_modes": modes]
        if let room { attributes["current_temperature"] = room }
        if let unit { attributes["temperature_unit"] = unit }
        if let action { attributes["hvac_action"] = action }
        let raw = try JSONSerialization.data(withJSONObject: ["entity_id": "climate.room", "state": mode,
            "attributes": attributes])
        var readings = ["climate.room": HaStateReading(entityID: "climate.room",
            json: String(decoding: raw, as: UTF8.self), checkedAt: now)]
        if context {
            readings["sensor.first"] = HaStateReading(entityID: "sensor.first",
                json: #"{"state":"48.1234","attributes":{"friendly_name":"Outside","unit_of_measurement":"°F"}}"#,
                checkedAt: now.addingTimeInterval(-30))
            readings["sensor.second"] = HaStateReading(entityID: "sensor.second",
                json: #"{"state":"19","attributes":{"friendly_name":"Bedroom","unit_of_measurement":"°C"}}"#,
                checkedAt: now)
        }
        let config = HaConfig(baseUrl: "https://example.invalid", token: authenticated ? "inert" : "",
            entityId: "", climateId: "climate.room",
            sensorsJson: context ? #"["sensor.first","sensor.second"]"# : "[]")
        return thermostatEnvelope(HaStoreSnapshot(config: config, scope: "inert",
            readings: readings, climateOperation: operation, failures: failures,
            thermostatSelectionRevision: UUID().uuidString), now: now, recovery: recovery)
    }

    func testSelectedContextExcludesTargetAndKeepsItsOwnFailureAndRawAccessibility() throws {
        let failure = HaStateFailure(message: "Inert", checkedAt: now, reason: .transport)
        let source = try envelope(failures: ["sensor.first": failure])
        let value = thermostatSmallContent(source.presentation)
        XCTAssertNil(value.target)
        XCTAssertNil(value.status)
        XCTAssertEqual(value.focused.roomAttribution, "Room")
        XCTAssertEqual(value.focused.context?.entityID, "sensor.first")
        XCTAssertEqual(value.focused.context?.availability, .lastKnown)
        let label = thermostatSmallAccessibility(value, locale: locale)
        XCTAssertTrue(label.contains("-2.56 °C"))
        XCTAssertTrue(label.contains("Outside, 48.1234 °F, Last known"))
        XCTAssertFalse(label.contains("Bedroom"))
        XCTAssertTrue(label.contains("inactive"))
    }

    func testActualActionDoesNotInferHeatingFromHeatOrBorrowUnknownUnits() throws {
        let heating = thermostatSmallContent(try envelope(mode: "heat", action: "heating", context: false).presentation)
        XCTAssertEqual(heating.mode, "Heating")
        XCTAssertEqual(heating.target, "20.1 °C")
        let configured = thermostatSmallContent(try envelope(mode: "heat", context: false).presentation)
        XCTAssertEqual(configured.mode, "Heat")
        let provider = thermostatSmallContent(try envelope(mode: "defrost", action: "defrosting", context: false).presentation)
        XCTAssertEqual(provider.mode, "Defrosting")
        XCTAssertNil(provider.target)
        let unknown = thermostatSmallContent(try envelope(unit: nil, context: false).presentation)
        XCTAssertNil(unknown.target)
        XCTAssertTrue(thermostatSmallAccessibility(unknown, locale: locale).contains("Unit not reported"))
    }

    func testRetainedRecoveryKeepsNumberDateAndSpecificWrittenHistory() throws {
        for (recovery, title) in [(ThermostatRecovery.authentication, "Sign in"),
            (.readFailed, "Check failed"), (.sharedStoreUnavailable, "Unavailable"),
            (.readingsNotSaved, "Not saved"), (.selectionChanged, "Changed")] {
            let source = try envelope(mode: "heat", action: "heating", context: false, recovery: recovery)
            let value = thermostatSmallContent(source.presentation)
            XCTAssertEqual(value.status, "Last known · \(title)")
            XCTAssertEqual(value.mode, "Heat")
            XCTAssertNil(value.target)
            XCTAssertEqual(value.focused.room.value, .number(-2.56))
            XCTAssertEqual(value.focused.room.checkedAt, now)
            XCTAssertTrue(thermostatSmallAccessibility(value, locale: locale).contains(title))
        }
    }

    func testPendingAndFailedMutationNeverBecomeAnObservedTargetOrProviderOutcome() throws {
        for (error, title) in [(Optional<String>.none, "Updating"), ("Applied", "Update failed")] {
            let operation = ClimateOperation(entityID: "climate.room", action: "heatUp", startedAt: now, error: error)
            let value = thermostatSmallContent(try envelope(mode: "heat", context: false, operation: operation).presentation)
            XCTAssertEqual(value.status, title)
            XCTAssertNil(value.target)
            XCTAssertEqual(value.focused.room.value, .number(-2.56))
            XCTAssertFalse(thermostatSmallAccessibility(value, locale: locale).contains("Applied"))
        }
    }

    func testMissingRoomStatesAndKnownZeroRemainDistinct() throws {
        let zero = thermostatSmallContent(try envelope(room: 0, unit: nil).presentation)
        XCTAssertEqual(thermostatFocusedNumberText(zero.focused.room, summary: true, locale: locale), "0")
        let missing = thermostatSmallContent(try envelope(room: nil).presentation)
        XCTAssertNil(thermostatFocusedNumberText(missing.focused.room, summary: true, locale: locale))
        XCTAssertEqual(missing.placeholder, "No reading")
        let unavailable = thermostatSmallContent(try envelope(mode: "unavailable").presentation)
        XCTAssertEqual(unavailable.placeholder, "Unavailable")
        let signIn = thermostatSmallContent(try envelope(room: nil, authenticated: false).presentation)
        XCTAssertEqual(signIn.placeholder, "Sign in")
        let setup = thermostatSmallContent(thermostatEnvelope(HaStoreSnapshot(config: nil, scope: "inert"), now: now).presentation)
        XCTAssertEqual(setup.placeholder, "Set up")
    }

    func testSmallNavigationRetainsOriginalSavedTicketAcrossRecoveryWithoutCreatingAnother() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThermostatTicketStore(directory: directory)
        let source = try envelope(context: false)
        let entry = bindThermostatEntry(source, date: now) { try store.save($0, now: now) }
        guard case let .ticket(id) = entry.destination else { return XCTFail("Real ticket must save") }
        let recovered = try envelope(context: false, recovery: .authentication)
        let value = thermostatSmallContent(recovered.presentation, destination: entry.destination)
        XCTAssertEqual(value.navigationURL?.absoluteString, "hearth://thermostat-readings/\(id.uuidString)")
        XCTAssertTrue(thermostatSmallAccessibility(value, locale: locale).contains("Open Hallway readings and controls"))
        XCTAssertEqual(try store.lookup(id, now: now), .available(try ThermostatTicket(evidence: source.evidence, issuedAt: now, id: id)))
        let unavailable = thermostatSmallContent(recovered.presentation, destination: .unavailable)
        XCTAssertEqual(unavailable.navigationURL?.absoluteString, "hearth://thermostat-readings/unavailable")
        XCTAssertNil(thermostatSmallContent(source.presentation, destination: .inert).navigationURL)
    }
    func testHealthySmallModeShortcutIsBoundAndNeverAdvertisedWithoutChoicesOrAuthority() throws {
        let id = UUID(), destination = ThermostatDestination.ticket(id)
        let healthy = thermostatSmallContent(try envelope(action: "idle", context: false).presentation,
            destination: destination)
        XCTAssertEqual(healthy.navigationURL?.absoluteString, "hearth://thermostat-mode/\(id)")
        XCTAssertEqual(healthy.actionLabel, "Mode")
        let label = thermostatSmallAccessibility(healthy, locale: locale)
        XCTAssertTrue(label.contains("Choose Hallway mode"))
        XCTAssertTrue(label.contains("Auto"))
        XCTAssertTrue(label.contains("Idle"))
        let noChoice = thermostatSmallContent(try envelope(context: false, modes: ["heat_cool"]).presentation,
            destination: destination)
        XCTAssertEqual(noChoice.navigationURL, thermostatReadingsURL(for: destination))
        XCTAssertEqual(noChoice.actionLabel, "Readings")
        let pending = ClimateOperation(entityID: "climate.room", action: "mode", startedAt: now)
        for source in [try envelope(context: false, operation: pending),
                       try envelope(context: false, recovery: .readFailed),
                       try envelope(mode: "unavailable", context: false)] {
            let content = thermostatSmallContent(source.presentation, destination: destination)
            XCTAssertEqual(content.navigationURL, thermostatReadingsURL(for: destination))
            XCTAssertEqual(content.actionLabel, "Readings")
            XCTAssertFalse(thermostatSmallAccessibility(content, locale: locale).contains("Choose Hallway mode"))
        }
        XCTAssertNil(thermostatSmallContent(try envelope().presentation).navigationURL)
        XCTAssertEqual(thermostatSmallContent(try envelope().presentation).actionLabel, "Mode")
        XCTAssertEqual(thermostatSmallContent(try envelope(authenticated: false).presentation,
            destination: destination).actionLabel, "Sign in")
        XCTAssertEqual(thermostatSmallContent(thermostatEnvelope(HaStoreSnapshot(config: nil,
            scope: "inert"), now: now).presentation, destination: destination).actionLabel, "Connect")
    }
}
