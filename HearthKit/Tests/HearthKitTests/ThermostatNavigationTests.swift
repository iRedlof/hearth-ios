import XCTest
@testable import HearthKit

final class ThermostatNavigationTests: XCTestCase {
    private let checked = Date(timeIntervalSince1970: 1_780_000_000)
    private var now: Date { checked.addingTimeInterval(86_400) }
    private func store() -> HaStateStore {
        HaStateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            initialConfig: HaConfig(baseUrl: "https://fixture.invalid", token: "private", entityId: "",
                climateId: "climate.room", resumeId: "button.resume", sensorsJson: #"["sensor.a","sensor.b"]"#))
    }
    private func context(_ store: HaStateStore, state: String = "heat",
                         room: String = "19.5") throws -> HaStoreSnapshot {
        let context = try store.snapshot()
        return try XCTUnwrap(store.merge([
            "climate.room": HaStateReading(entityID: "climate.room",
                json: #"{"entity_id":"climate.room","state":"\#(state)","attributes":{"current_temperature":\#(room),"temperature":20,"temperature_unit":"°C","hvac_modes":["heat","cool"],"min_temp":7,"max_temp":35,"target_temp_step":0.5}}"#,
                checkedAt: checked),
            "sensor.a": HaStateReading(entityID: "sensor.a",
                json: #"{"state":"4","attributes":{"unit_of_measurement":"°C"}}"#,
                checkedAt: checked.addingTimeInterval(30))
        ], expectedScope: context.scope))
    }
    func testAutomaticLoadsNeverRequestAndPreserveActualSavedObservation() async throws {
        let store = store(), context = try context(store)
        let loader = ThermostatLiveLoader(load: { _ in try store.snapshot() },
            merge: { result, origin, revision, date in
                try store.merge(result.readings, expectedScope: origin?.scope ?? "",
                    expectedClimateRevision: revision,
                    expectedThermostatSelectionRevision: origin?.selectionRevision, failures: result.errors, checkedAt: date)
            }, request: { _ in XCTFail("Automatic cache must never request"); return "{}" })
        for cause in [ThermostatForegroundLoadCause.initialOrConfig, .cacheChanged, .chargepointSignIn] {
            let result = await loader.load(cause: cause, now: now)
            XCTAssertEqual(result.evidence.readings, context.readings)
            XCTAssertEqual(thermostatSavedObservation(result.presentation), checked)
            XCTAssertEqual(result.presentation.room.availability, .current)
        }
    }
    func testSavedObservationIsIndependentOfNumericRoomAndSensorTimes() throws {
        for (state, room) in [("heat", "19.5"), ("unknown", "19.5"), ("unavailable", "19.5"),
                              ("heat", "null"), ("heat", "true")] {
            let context = try context(store(), state: state, room: room)
            let value = thermostatEnvelope(context, now: now)
            XCTAssertEqual(thermostatSavedObservation(value.presentation), checked)
            XCTAssertEqual(value.presentation.sensors.first?.checkedAt, checked.addingTimeInterval(30))
            if state != "heat" || room == "null" || room == "true" {
                XCTAssertNil(value.presentation.room.value)
            }
        }
        let empty = thermostatEnvelope(try store().snapshot(), now: now)
        XCTAssertNil(thermostatSavedObservation(empty.presentation))
        let date = thermostatObservationText(checked, locale: Locale(identifier: "en_US"),
            zone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(date.contains("2026"), date)
    }
    func testTargetFactsRemainReadOnlyAndPartialAutoDisclosesMissingEndpoint() throws {
        let store = store(), initial = try store.snapshot()
        let json = #"{"entity_id":"climate.room","state":"heat_cool","attributes":{"current_temperature":21,"target_temp_low":19.125,"target_temp_high":24.625,"temperature_unit":"°C","min_temp":7,"max_temp":35,"target_temp_step":0.125}}"#
        let saved = try XCTUnwrap(store.merge(["climate.room": HaStateReading(
            entityID: "climate.room", json: json, checkedAt: checked)], expectedScope: initial.scope))
        let ticket = try ThermostatTicket(evidence: thermostatEnvelope(saved).evidence, issuedAt: now)
        let failed = try XCTUnwrap(store.merge([:], expectedScope: saved.scope,
            failures: ["climate.room": "Couldn't connect"], checkedAt: now))
        var session = ThermostatRouteSession(ticket: ticket, context: failed, now: now)
        XCTAssertNil(session.controlOrigin)
        XCTAssertEqual(thermostatTargetFacts(session.shownEnvelope.presentation).map(\.value), [19.125, 24.625])
        XCTAssertEqual(session.shownEnvelope.presentation.room.checkedAt, checked)
        session.reconcile(context: failed, now: ticket.expiresAt)
        XCTAssertEqual(session.status, .expired)
        XCTAssertNil(session.controlOrigin)
        XCTAssertEqual(thermostatTargetFacts(session.shownEnvelope.presentation).map(\.value), [19.125, 24.625])

        var partial = ticket.evidence
        partial.readings["climate.room"] = HaStateReading(entityID: "climate.room",
            json: json.replacingOccurrences(of: #""target_temp_high":24.625,"#, with: ""), checkedAt: checked)
        let envelope = ThermostatLiveEnvelope(evidence: partial)
        XCTAssertFalse(envelope.presentation.state?.canSetTemperature == true)
        let facts = thermostatTargetFacts(envelope.presentation)
        XCTAssertEqual(facts.map(\.kind), [.heat, .cool])
        XCTAssertEqual(facts.map(\.value), [19.125, nil])
        XCTAssertEqual(facts.last?.valueText(locale: Locale(identifier: "en_US")), "Not reported")
    }
    func testTargetFactsUseRawFinePrecisionAndReportedOrUnknownUnit() throws {
        let initial = try store().snapshot()
        for unit in [#","temperature_unit":"K""#, ""] {
            var evidence = thermostatEnvelope(initial).evidence
            evidence.readings["climate.room"] = HaStateReading(entityID: "climate.room",
                json: #"{"entity_id":"climate.room","state":"heat","attributes":{"current_temperature":19.375,"temperature":20.125,"min_temp":7,"max_temp":35,"target_temp_step":0.125\#(unit)}}"#,
                checkedAt: checked)
            let envelope = ThermostatLiveEnvelope(evidence: evidence)
            let facts = thermostatTargetFacts(envelope.presentation)
            XCTAssertEqual(facts.map(\.kind), [.heat])
            XCTAssertEqual(facts.first?.value, 20.125)
            XCTAssertEqual(facts.first?.reportedUnit, unit.isEmpty ? nil : "K")
            XCTAssertEqual(facts.first?.valueText(locale: Locale(identifier: "en_US")), unit.isEmpty ? "20.125" : "20.125 K")
            XCTAssertEqual(facts.first?.valueText(locale: Locale(identifier: "fr_FR")), unit.isEmpty ? "20,125" : "20,125 K")
            // The ordinary widget's legacy presentation is intentionally unchanged.
            XCTAssertEqual(envelope.snapshot.heatSetpoint, "20.1°")
        }
    }
    func testHeatAndCoolDisplayTheSingleTargetTheirCommandsActuallyChange() throws {
        let initial = try store().snapshot()
        for (mode, kind, action) in [("heat", ThermostatTargetKind.heat, "heatUp"),
                                     ("cool", ThermostatTargetKind.cool, "coolUp")] {
            var evidence = thermostatEnvelope(initial).evidence
            evidence.readings["climate.room"] = HaStateReading(entityID: "climate.room",
                json: #"{"entity_id":"climate.room","state":"\#(mode)","attributes":{"temperature":20,"target_temp_low":18,"target_temp_high":24,"temperature_unit":"°C","min_temp":7,"max_temp":35,"target_temp_step":0.5}}"#,
                checkedAt: checked)
            let presentation = ThermostatLiveEnvelope(evidence: evidence).presentation
            let facts = thermostatTargetFacts(presentation)
            XCTAssertEqual(facts.map(\.kind), [kind])
            XCTAssertEqual(facts.map(\.value), [20])
            let command = try XCTUnwrap(climateCommand(try XCTUnwrap(presentation.state),
                entityID: "climate.room", action: action))
            XCTAssertEqual(command.temperatures, ["temperature": 20.5])
        }
    }
    func testOtherReportedEndpointsAreSeparateForSingleOffAndUnknownModes() throws {
        let initial = try store().snapshot()
        let attributes = #""temperature":20.125,"target_temp_low":18.125,"target_temp_high":24.625,"temperature_unit":"K","min_temp":7,"max_temp":35,"target_temp_step":0.125"#
        func presentation(_ mode: String, _ attributes: String) -> ThermostatPresentation {
            var evidence = thermostatEnvelope(initial).evidence
            evidence.readings["climate.room"] = HaStateReading(entityID: "climate.room",
                json: #"{"entity_id":"climate.room","state":"\#(mode)","attributes":{\#(attributes)}} "#,
                checkedAt: checked)
            return ThermostatLiveEnvelope(evidence: evidence).presentation
        }
        for mode in ["heat", "cool", "off", "unknown", "unavailable"] {
            let value = presentation(mode, attributes)
            XCTAssertEqual(thermostatTargetFacts(value).map(\.value), [20.125])
            let other = thermostatOtherReportedTargets(value)
            XCTAssertEqual(other.map(\.kind), [.lowerEndpoint, .upperEndpoint])
            XCTAssertEqual(other.map(\.kind.title), ["Lower endpoint", "Upper endpoint"])
            XCTAssertEqual(other.map(\.value), [18.125, 24.625])
            XCTAssertEqual(other.map { $0.valueText(locale: Locale(identifier: "en_US")) }, ["18.125 K", "24.625 K"])
            if ["off", "unknown", "unavailable"].contains(mode) {
                XCTAssertNil(climateCommand(try XCTUnwrap(value.state), entityID: "climate.room", action: "heatUp"))
            }
        }
        let partial = attributes.replacingOccurrences(of: #""target_temp_high":24.625,"#, with: "")
        let facts = thermostatOtherReportedTargets(presentation("unknown", partial))
        XCTAssertEqual(facts.map(\.value), [18.125, nil])
        XCTAssertEqual(facts.last?.valueText(), "Not reported")
        let noUnit = partial.replacingOccurrences(of: #""temperature_unit":"K","#, with: "")
        let unknownUnit = thermostatOtherReportedTargets(presentation("off", noUnit))
        XCTAssertNil(unknownUnit.first?.reportedUnit)
        XCTAssertEqual(unknownUnit.first?.valueText(locale: Locale(identifier: "en_US")), "18.125")
        XCTAssertTrue(thermostatOtherReportedTargets(presentation("heat_cool", attributes)).isEmpty)
        let absent = noUnit.replacingOccurrences(of: #""target_temp_low":18.125,"#, with: "")
        XCTAssertTrue(thermostatOtherReportedTargets(presentation("off", absent)).isEmpty)
    }
    func testStrictOpaqueURLsRejectAmbiguousInputs() {
        let id = UUID(), destination = ThermostatDestination.ticket(id)
        XCTAssertEqual(thermostatDestination(from: thermostatReadingsURL(for: destination)!), destination)
        XCTAssertNil(thermostatReadingsURL(for: .inert))
        for text in ["hearth://thermostat-readings/\(id)?x=1", "hearth://thermostat-readings/\(id)#x",
                     "hearth://user@thermostat-readings/\(id)", "hearth://thermostat-readings:80/\(id)",
                     "hearth://thermostat-readings/%75navailable", "hearth://thermostat-readings/\(id)/extra",
                     "hearth://thermostat-readings/", "https://thermostat-readings/\(id)"] {
            XCTAssertNil(thermostatDestination(from: URL(string: text)!), text)
        }
    }
    func testTicketStoreImmutableSaveExpiryAndMissingWithoutDefaultFallback() throws {
        let context = try context(store())
        let ticket = try ThermostatTicket(evidence: thermostatEnvelope(context).evidence, issuedAt: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tickets = ThermostatTicketStore(directory: directory)
        try tickets.save(ticket, now: now)
        let before = try Data(contentsOf: directory.appendingPathComponent("thermostat-readings-tickets.json"))
        try tickets.save(ticket, now: now.addingTimeInterval(1))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("thermostat-readings-tickets.json")), before)
        XCTAssertEqual(try tickets.lookup(ticket.id, now: now), .available(ticket))
        XCTAssertEqual(try tickets.lookup(UUID(), now: now), .missing)
        XCTAssertEqual(try tickets.lookup(ticket.id, now: ticket.expiresAt), .expired)
        var evidence = ticket.evidence; evidence.recovery = .readFailed
        let changed = try ThermostatTicket(evidence: evidence, issuedAt: now, id: ticket.id)
        XCTAssertThrowsError(try tickets.save(changed, now: now))
        let text = String(decoding: before, as: UTF8.self)
        XCTAssertFalse(text.contains("private")); XCTAssertFalse(text.contains("fixture.invalid"))
    }
    func testTicketBoundsEvictOldestKeepIncomingAndRejectCorruption() throws {
        let evidence = thermostatEnvelope(try context(store())).evidence
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tickets = ThermostatTicketStore(directory: directory, maximumCount: 2)
        let values = try (0..<3).map { try ThermostatTicket(evidence: evidence, issuedAt: now.addingTimeInterval(Double($0))) }
        for ticket in values { try tickets.save(ticket, now: ticket.issuedAt) }
        XCTAssertEqual(try tickets.lookup(values[0].id, now: now), .missing)
        XCTAssertEqual(try tickets.lookup(values[2].id, now: now), .available(values[2]))
        XCTAssertThrowsError(try ThermostatTicketStore(directory: directory, maximumTicketBytes: 16)
            .save(values[2], now: now))
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("thermostat-readings-tickets.json"))
        XCTAssertThrowsError(try tickets.lookup(values[2].id, now: now))
    }
    func testFailedTicketSaveRetainsEvidenceAndPublishesUnavailable() throws {
        let envelope = thermostatEnvelope(try context(store()))
        let payload = bindThermostatEntry(envelope, date: now) { _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertEqual(payload.destination, .unavailable)
        XCTAssertEqual(payload.presentation.room.checkedAt, checked)
        XCTAssertEqual(payload.presentation.recovery, .readingsNotSaved)
        XCTAssertFalse(payload.presentation.authorityAvailable)
    }
    func testAllSelectionABAChangesPermanentlyRetireOpening() throws {
        for field in 0..<4 {
            let store = store(), original = try context(store)
            let ticket = try ThermostatTicket(evidence: thermostatEnvelope(original).evidence, issuedAt: now)
            var session = ThermostatRouteSession(ticket: ticket, context: original, now: now)
            let first = try XCTUnwrap(original.config)
            var other = first
            switch field {
            case 0: other.climateId = "climate.other"
            case 1: other.resumeId = "button.other"
            case 2: other.sensorsJson = #"["sensor.c"]"#
            default: other.sensorsJson = #"["sensor.b","sensor.a"]"#
            }
            _ = try store.saveConfig(other); let returned = try store.saveConfig(first)
            session.reconcile(context: returned, now: now)
            XCTAssertEqual(session.status, .selectionChanged)
            XCTAssertNil(session.controlOrigin)
            XCTAssertEqual(session.openingTicket, ticket)
            XCTAssertEqual(session.shownEnvelope.evidence.readings, ticket.evidence.readings)
            session.reconcile(context: original, now: now)
            XCTAssertEqual(session.status, .selectionChanged)
        }
    }
    func testSameSelectionCommandsRefreshControlRevisionButRetainedButtonsStayOld() throws {
        let store = store(), context = try context(store)
        let ticket = try ThermostatTicket(evidence: thermostatEnvelope(context).evidence, issuedAt: now)
        var session = ThermostatRouteSession(ticket: ticket, context: context, now: now)
        let old = try XCTUnwrap(session.controlOrigin)
        let begun = try XCTUnwrap(store.beginClimateOperation(expectedScope: context.scope,
            expectedRevision: old.revision, entityID: "climate.room", action: "heatUp", now: now))
        session.reconcile(context: begun, now: now)
        XCTAssertNil(session.controlOrigin)
        let finished = try XCTUnwrap(store.finishClimateOperation(expectedScope: context.scope,
            operationID: begun.climateOperation!.id, error: nil))
        session.reconcile(context: finished, now: now)
        XCTAssertEqual(session.status, .current)
        XCTAssertNotEqual(session.controlOrigin?.revision, old.revision)
        XCTAssertEqual(session.openingTicket, ticket)
        XCTAssertNil(try store.beginClimateOperation(expectedScope: old.selection.scope,
            expectedRevision: old.revision, entityID: old.selection.entityID, action: "heatUp"))
    }
    func testDuplicateAdmissionRetainsEventTaskPickerAndExpiryButRevalidates() throws {
        let context = try context(store())
        let ticket = try ThermostatTicket(evidence: thermostatEnvelope(context).evidence, issuedAt: now)
        var admission = ThermostatRouteAdmission()
        let request = try XCTUnwrap(admission.admit(.ticket(ticket.id)))
        XCTAssertEqual(admission.admit(.ticket(ticket.id)), request)
        var session = ThermostatRouteSession(ticket: ticket, context: context, now: now)
        let task = UUID(), picker = UUID()
        session.pickerID = picker
        let claim = try XCTUnwrap(session.beginRefresh(requestID: request.eventID, taskID: task, context: context, now: now))
        XCTAssertEqual(admission.admit(.ticket(ticket.id)), request)
        session.reconcile(context: context, now: now)
        XCTAssertEqual(session.refreshClaim, claim); XCTAssertEqual(session.pickerID, picker)
        session.reconcile(context: context, now: ticket.expiresAt)
        XCTAssertEqual(session.status, .expired)
        XCTAssertNil(session.refreshClaim); XCTAssertNil(session.pickerID); XCTAssertNil(session.controlOrigin)
        XCTAssertEqual(session.openingTicket.expiresAt, ticket.expiresAt)
        session.reconcile(context: context, now: now)
        XCTAssertEqual(session.status, .expired)
        admission.close()
        XCTAssertNotEqual(admission.admit(.ticket(ticket.id))?.eventID, request.eventID)
    }
    func testClosedOrReplacedRefreshCannotPublishAndRecoveryReturnIsOwned() throws {
        let context = try context(store())
        let ticket = try ThermostatTicket(evidence: thermostatEnvelope(context).evidence, issuedAt: now)
        var session = ThermostatRouteSession(ticket: ticket, context: context, now: now)
        let claim = try XCTUnwrap(session.beginRefresh(requestID: UUID(), taskID: UUID(), context: context, now: now))
        session.close()
        XCTAssertFalse(session.finishRefresh(claim: claim, envelope: thermostatEnvelope(context),
            context: context, now: now))
        var admission = ThermostatRouteAdmission()
        let original = try XCTUnwrap(admission.admit(.ticket(ticket.id)))
        admission.close()
        let reopened = try XCTUnwrap(admission.returning(original, replacing: nil))
        XCTAssertNotEqual(original.eventID, reopened.eventID)
        let newer = try XCTUnwrap(admission.admit(.ticket(UUID())))
        XCTAssertNil(admission.returning(original, replacing: reopened.eventID))
        XCTAssertEqual(admission.active, newer)
    }
}
