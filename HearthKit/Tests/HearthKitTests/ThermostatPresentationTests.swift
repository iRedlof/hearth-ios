import XCTest
@testable import HearthKit

final class ThermostatPresentationTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_800_000_000)
    private let generation = "714D219A-11A6-486E-BC9D-78AB67669F84"
    private let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "",
        climateId: "climate.room", resumeId: "button.resume",
        sensorsJson: #"["sensor.context","sensor.bedroom","sensor.context","sensor.third","sensor.fourth"]"#)

    private func climate(_ room: String = "-2.5", mode: String = "auto", unit: String = #""°C""#) -> HaStateReading {
        HaStateReading(entityID: "climate.room", json: """
        {"entity_id":"climate.room","state":"\(mode)","last_changed":"2026-10-01T10:00:00Z",
        "attributes":{"friendly_name":"Hallway","current_temperature":\(room),"current_humidity":54,
        "temperature_unit":\(unit),"target_temp_low":7,"target_temp_high":12,
        "min_temp":7,"max_temp":35,"target_temp_step":0.5,"hvac_modes":["off","auto"]}}
        """, checkedAt: observed)
    }

    private func sensor(_ id: String, value: String = "18.5", unit: String = "°F") -> HaStateReading {
        HaStateReading(entityID: id, json: """
        {"entity_id":"\(id)","state":"\(value)","attributes":{"friendly_name":"Named \(id)","unit_of_measurement":"\(unit)"}}
        """, checkedAt: observed.addingTimeInterval(5))
    }

    private func context(room: HaStateReading? = nil, failures: [String: HaStateFailure] = [:],
                         operation: ClimateOperation? = nil) -> HaStoreSnapshot {
        var readings = ["climate.room": room ?? climate()]
        for id in ["sensor.context", "sensor.bedroom", "sensor.third", "sensor.fourth"] {
            readings[id] = sensor(id)
        }
        return HaStoreSnapshot(config: config, scope: "scope", readings: readings,
            climateRevision: "control", climateOperation: operation, failures: failures,
            thermostatSelectionRevision: generation)
    }

    func testCurrentRawRoomAndContextPreserveSourceUnitAndIndependentTimes() throws {
        let value = thermostatPresentation(context())
        XCTAssertEqual(value.room.value, .number(-2.5))
        XCTAssertEqual(value.room.reportedUnit, "°C")
        XCTAssertEqual(value.room.availability, .current)
        XCTAssertEqual(value.room.checkedAt, observed)
        XCTAssertNotNil(value.room.lastChanged)
        XCTAssertEqual(value.room.source, .homeAssistantClimate)
        XCTAssertEqual(value.sensors.map(\.entityID), ["sensor.context", "sensor.bedroom", "sensor.third"])
        XCTAssertEqual(value.sensors[0].name, "Named sensor.context")
        XCTAssertEqual(value.sensors[0].source, .homeAssistantSensor)
        XCTAssertEqual(value.sensors[0].reportedUnit, "°F")
        XCTAssertEqual(value.sensors[0].checkedAt, observed.addingTimeInterval(5))
        XCTAssertEqual(value.origin?.selectedSensorIDs, config.sensorIds)
        XCTAssertEqual(value.configuration, .ready)
        XCTAssertTrue(value.authorityAvailable)
        XCTAssertEqual(value.unfetchedSensorIDs, ["sensor.fourth"])
        let evidence = thermostatEnvelope(context()).evidence
        XCTAssertEqual(evidence.selectedSensorIDs, config.sensorIds)
        XCTAssertEqual(evidence.fetchedSensorIDs, ["sensor.context", "sensor.bedroom", "sensor.third"])
        XCTAssertEqual(Set(evidence.readings.keys),
            Set(["climate.room", "sensor.context", "sensor.bedroom", "sensor.third"]))
        XCTAssertNil(evidence.readings["sensor.fourth"])
        let foreign = HaStateReading(entityID: "sensor.foreign", json: #"{"state":"88"}"#, checkedAt: observed)
        let original = context()
        var records = original.readings; records["sensor.foreign"] = foreign
        let filtered = thermostatEnvelope(HaStoreSnapshot(config: config, scope: original.scope,
            readings: records, failures: ["sensor.foreign": HaStateFailure(message: "foreign", checkedAt: observed)],
            thermostatSelectionRevision: generation)).evidence
        XCTAssertNil(filtered.readings["sensor.foreign"])
        XCTAssertNil(filtered.failures["sensor.foreign"])
        var privateConfig = config
        privateConfig.token = "inert-private-token"; privateConfig.refreshToken = "inert-private-refresh"
        let transferable = thermostatEnvelope(HaStoreSnapshot(config: privateConfig, scope: "scope",
            readings: records, thermostatSelectionRevision: generation)).evidence
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(transferable), encoding: .utf8))
        XCTAssertFalse(encoded.contains(privateConfig.token))
        XCTAssertFalse(encoded.contains(privateConfig.refreshToken))
        XCTAssertFalse(encoded.contains(privateConfig.baseUrl))
    }

    func testAbsentOrMalformedClimateUnitNeverBorrowsSensorUnitOrDefaults() {
        for unit in ["null", "false", "1", #""""#] {
            let value = thermostatPresentation(context(room: climate(unit: unit)))
            XCTAssertNil(value.room.reportedUnit, unit)
            XCTAssertEqual(value.room.value, .number(-2.5), unit)
            XCTAssertEqual(value.sensors.first?.reportedUnit, "°F", unit)
        }
        var record = climate()
        record = HaStateReading(entityID: record.entityID,
            json: record.json.replacingOccurrences(of: #""temperature_unit":"°C","#, with: ""),
            checkedAt: record.checkedAt)
        XCTAssertNil(thermostatPresentation(context(room: record)).room.reportedUnit)
    }

    func testFailedEntitiesKeepTheirOwnHistoryWithoutAffectingSuccessfulRows() {
        let failure = HaStateFailure(message: "arbitrary text", checkedAt: observed.addingTimeInterval(60),
            reason: .transport)
        let failedRoom = thermostatPresentation(context(failures: ["climate.room": failure]))
        XCTAssertEqual(failedRoom.room.availability, .lastKnown)
        XCTAssertEqual(failedRoom.room.value, .number(-2.5))
        XCTAssertEqual(failedRoom.room.checkedAt, observed)
        XCTAssertEqual(failedRoom.room.failure?.reason, .transport)
        XCTAssertTrue(failedRoom.sensors.allSatisfy { $0.availability == .current })
        XCTAssertFalse(failedRoom.authorityAvailable)
        let failedSensor = thermostatPresentation(context(failures: ["sensor.context": failure]))
        XCTAssertEqual(failedSensor.room.availability, .current)
        XCTAssertEqual(failedSensor.sensors[0].availability, .lastKnown)
        XCTAssertEqual(failedSensor.sensors[1].availability, .current)
        XCTAssertEqual(failedSensor.sensors[0].checkedAt, observed.addingTimeInterval(5))
        XCTAssertTrue(failedSensor.authorityAvailable)
    }

    func testSuccessfulMissingMalformedOrUnavailableRoomDoesNotInventHistoricalNumber() {
        for raw in ["null", "true", #""not a number""#] {
            let value = thermostatPresentation(context(room: climate(raw)))
            XCTAssertNil(value.room.value, raw)
            XCTAssertEqual(value.room.availability, .noReading, raw)
            XCTAssertEqual(value.room.checkedAt, observed, raw)
            XCTAssertEqual(value.state?.low, 7, raw)
            XCTAssertTrue(value.authorityAvailable, "Room absence does not erase valid target capabilities")
        }
        let unavailable = thermostatPresentation(context(room: climate("null", mode: "unavailable")))
        XCTAssertEqual(unavailable.room.availability, .unavailable)
        XCTAssertNil(unavailable.room.value)
        XCTAssertFalse(unavailable.authorityAvailable)
    }

    func testSyntheticContextIsUnboundAndConfigurationReasonsRemainDistinct() {
        let synthetic = HaStoreSnapshot(config: config, scope: "scope", readings: context().readings)
        XCTAssertNil(thermostatPresentation(synthetic).origin)
        XCTAssertFalse(thermostatPresentation(synthetic).authorityAvailable)
        XCTAssertEqual(thermostatPresentation(synthetic).room.value, .number(-2.5))
        XCTAssertEqual(thermostatEnvelope(synthetic).evidence.selectedSensorIDs, config.sensorIds)
        let invalidGeneration = HaStoreSnapshot(config: config, scope: "scope",
            thermostatSelectionRevision: "initial")
        XCTAssertNil(thermostatPresentation(invalidGeneration).origin)
        var unauthenticated = config; unauthenticated.token = ""
        XCTAssertEqual(thermostatPresentation(HaStoreSnapshot(config: unauthenticated, scope: "scope",
            thermostatSelectionRevision: generation)).configuration, .needsAuthentication)
        XCTAssertEqual(thermostatPresentation(HaStoreSnapshot(config: nil, scope: "scope",
            thermostatSelectionRevision: generation)).configuration, .unconfigured)
        var invalid = config; invalid.baseUrl = "http://example.com"
        XCTAssertEqual(thermostatPresentation(HaStoreSnapshot(config: invalid, scope: "scope",
            thermostatSelectionRevision: generation)).configuration, .invalid)
    }

    func testRecoveryAndOperationFacetsDoNotManufactureTelemetryOrProviderOutcomes() {
        let pending = ClimateOperation(entityID: "climate.room", action: "mode", startedAt: observed)
        let value = thermostatEnvelope(context(operation: pending), now: observed.addingTimeInterval(30))
        XCTAssertEqual(value.presentation.operation, .pending(pending))
        XCTAssertEqual(value.presentation.room.checkedAt, observed)
        XCTAssertTrue(value.snapshot.commandPending)
        XCTAssertFalse(value.snapshot.canPickMode)
        var failed = pending; failed.error = "arbitrary failure"
        XCTAssertEqual(thermostatPresentation(context(operation: failed)).operation, .failed(failed))
        for recovery in [ThermostatRecovery.readingsNotSaved, .selectionChanged, .operationNotSaved] {
            let envelope = thermostatEnvelope(context(), now: observed.addingTimeInterval(30), recovery: recovery)
            XCTAssertEqual(envelope.presentation.recovery, recovery)
            XCTAssertEqual(envelope.presentation.room.checkedAt, observed)
            XCTAssertFalse(envelope.presentation.authorityAvailable)
            XCTAssertFalse(envelope.snapshot.canAdjustHeatUp)
            XCTAssertFalse(envelope.snapshot.setup)
        }
    }

    func testContextFreeStorageFailureHasNoOriginReadingsTimeOrCommandAuthority() {
        let envelope = thermostatStorageUnavailableEnvelope(now: observed)
        XCTAssertNil(envelope.evidence.origin)
        XCTAssertEqual(envelope.presentation.configuration, .unavailable)
        XCTAssertEqual(envelope.presentation.recovery, .sharedStoreUnavailable)
        XCTAssertTrue(envelope.evidence.readings.isEmpty)
        XCTAssertTrue(envelope.evidence.failures.isEmpty)
        XCTAssertNil(envelope.presentation.room.value)
        XCTAssertNil(envelope.presentation.room.checkedAt)
        XCTAssertNil(envelope.presentation.room.lastChanged)
        XCTAssertEqual(envelope.presentation.operation, .none)
        XCTAssertFalse(envelope.presentation.authorityAvailable)
        XCTAssertEqual(envelope.snapshot.checkedAt, "—")
        XCTAssertFalse(envelope.snapshot.setup)
        XCTAssertFalse(envelope.snapshot.canPickMode)
        XCTAssertFalse(envelope.snapshot.canResume)
    }

    func testAuthenticationRecoveryKeepsOrdinarySignInFooterReachable() {
        let refusal = HaStateFailure(message: "arbitrary words", checkedAt: observed.addingTimeInterval(60),
            reason: .authentication)
        let rejectedRead = thermostatEnvelope(context(failures: ["climate.room": refusal]), now: observed)
        var signedOut = config; signedOut.token = ""; signedOut.refreshToken = ""
        let missingAuth = thermostatEnvelope(HaStoreSnapshot(config: signedOut, scope: "scope",
            readings: context().readings, thermostatSelectionRevision: generation), now: observed)
        for (variant, envelope) in [("rejected read", rejectedRead), ("missing authentication", missingAuth)] {
            XCTAssertEqual(envelope.presentation.recovery, .authentication)
            XCTAssertEqual(envelope.presentation.room.value, .number(-2.5), variant)
            XCTAssertEqual(envelope.presentation.room.reportedUnit, "°C", variant)
            XCTAssertEqual(envelope.presentation.room.checkedAt, observed, variant)
            XCTAssertEqual(envelope.presentation.origin?.selectionRevision, generation, variant)
            XCTAssertFalse(envelope.presentation.authorityAvailable, variant)
            XCTAssertEqual(envelope.snapshot.roomTemp, "-2.5°", variant)
            XCTAssertEqual(envelope.snapshot.roomSub, "Last known", variant)
            XCTAssertTrue(envelope.snapshot.stale, variant)
            XCTAssertEqual(envelope.snapshot.tone, .offline, variant)
            XCTAssertEqual(thermostatFocusedContent(envelope.presentation, accessibility: false).roomAttribution,
                "Last known", variant)
            XCTAssertTrue(envelope.snapshot.needsSignIn)
            XCTAssertTrue(envelope.snapshot.needsSettings, "The ordinary footer uses this flag to render Sign in")
            XCTAssertFalse(envelope.snapshot.setup)
            XCTAssertFalse(envelope.snapshot.canPickMode)
            XCTAssertFalse(envelope.snapshot.canResume)
        }
    }

    func testSuccessfulUnavailableOrUnknownRoomMatchesTypedSnapshotWithoutHistoricalNumber() {
        for mode in ["unavailable", "unknown"] {
            let envelope = thermostatEnvelope(context(room: climate("-2.5", mode: mode)), now: observed)
            XCTAssertEqual(envelope.presentation.state?.current, -2.5, "Raw evidence remains inspectable")
            XCTAssertEqual(envelope.presentation.room.availability, .unavailable)
            XCTAssertNil(envelope.presentation.room.value)
            XCTAssertEqual(envelope.presentation.room.checkedAt, observed)
            XCTAssertEqual(envelope.snapshot.roomTemp, "—")
            XCTAssertEqual(envelope.snapshot.roomSub, "No reading")
            XCTAssertFalse(envelope.snapshot.stale, "A successful unavailable reply is not a historical numeric sample")
            XCTAssertFalse(envelope.snapshot.canAdjustHeatUp)
        }
    }

    func testRelativeHumidityProjectionRejectsOutOfRangeWhileKeepingRawState() {
        for humidity in [-1.0, 101.0] {
            let original = climate()
            let record = HaStateReading(entityID: original.entityID,
                json: original.json.replacingOccurrences(of: #""current_humidity":54"#,
                    with: #""current_humidity":\#(humidity)"#), checkedAt: observed)
            let envelope = thermostatEnvelope(context(room: record), now: observed)
            XCTAssertEqual(envelope.presentation.state?.humidity, humidity)
            XCTAssertNil(envelope.presentation.humidity)
            XCTAssertNil(envelope.snapshot.humidity)
        }
        for humidity in [0.0, 100.0] {
            let original = climate()
            let record = HaStateReading(entityID: original.entityID,
                json: original.json.replacingOccurrences(of: #""current_humidity":54"#,
                    with: #""current_humidity":\#(humidity)"#), checkedAt: observed)
            XCTAssertEqual(thermostatPresentation(context(room: record)).humidity, humidity)
        }
    }

    func testIdleCacheWithoutClimateObservationDoesNotClaimARequestIsChecking() {
        let empty = HaStoreSnapshot(config: config, scope: "scope",
            thermostatSelectionRevision: generation)
        let envelope = thermostatEnvelope(empty, now: observed)
        XCTAssertEqual(envelope.snapshot.status, "No saved reading")
        XCTAssertNil(envelope.presentation.room.checkedAt)
        XCTAssertNil(envelope.presentation.room.value)
        XCTAssertFalse(envelope.snapshot.canAdjustHeatUp)
        for record in [climate("null"), climate("null", mode: "unavailable")] {
            let saved = thermostatEnvelope(context(room: record), now: observed)
            XCTAssertNotEqual(saved.snapshot.status, "No saved reading")
            XCTAssertEqual(saved.presentation.room.checkedAt, observed)
        }
    }

    func testFocusedRoomAndFirstContextKeepIndependentFactsAndReportedUnits() {
        let current = thermostatFocusedContent(thermostatPresentation(context()), accessibility: false)
        XCTAssertEqual(current.room.value, .number(-2.5))
        XCTAssertEqual(current.room.reportedUnit, "°C")
        XCTAssertEqual(current.roomAttribution, "Room")
        XCTAssertEqual(current.context?.entityID, "sensor.context")
        XCTAssertEqual(current.context?.name, "Named sensor.context")
        XCTAssertEqual(current.context?.reportedUnit, "°F")
        XCTAssertEqual(current.mode, "Auto")
        XCTAssertEqual(current.target, "7–12 °C")
        let failure = HaStateFailure(message: "In the room", checkedAt: observed, reason: .transport)
        let historical = thermostatFocusedContent(
            thermostatPresentation(context(failures: ["climate.room": failure])), accessibility: false)
        XCTAssertEqual(historical.roomAttribution, "Last known")
        XCTAssertEqual(historical.room.value, .number(-2.5))
        XCTAssertEqual(historical.room.checkedAt, observed)
        XCTAssertEqual(historical.context?.availability, .current)
        XCTAssertEqual(historical.tone, .offline)
        let failedContext = thermostatFocusedContent(
            thermostatPresentation(context(failures: ["sensor.context": failure])), accessibility: false)
        XCTAssertEqual(failedContext.roomAttribution, "Room")
        XCTAssertEqual(failedContext.context?.availability, .lastKnown)
        XCTAssertEqual(failedContext.context?.entityID, "sensor.context")
    }

    func testFocusedMissingContextNeverSubstitutesAnotherSensorOrInventsOutside() {
        let original = context()
        var records = original.readings
        records.removeValue(forKey: "sensor.context")
        let missing = thermostatFocusedContent(thermostatPresentation(HaStoreSnapshot(
            config: config, scope: "scope", readings: records, thermostatSelectionRevision: generation)),
            accessibility: false)
        XCTAssertEqual(missing.context?.entityID, "sensor.context")
        XCTAssertEqual(missing.context?.availability, .noReading)
        XCTAssertNil(missing.context?.value)
        var noSensors = config; noSensors.sensorsJson = "[]"
        let none = thermostatFocusedContent(thermostatPresentation(HaStoreSnapshot(
            config: noSensors, scope: "scope", readings: records, thermostatSelectionRevision: generation)),
            accessibility: false)
        XCTAssertNil(none.context)
    }

    func testFocusedPartialRangeAndUnknownUnitsNeverBecomeACompleteTarget() {
        let unknownUnit = thermostatFocusedContent(
            thermostatPresentation(context(room: climate(unit: "null"))), accessibility: false)
        XCTAssertNil(unknownUnit.room.reportedUnit)
        XCTAssertEqual(unknownUnit.room.value, .number(-2.5))
        XCTAssertNil(unknownUnit.target, "No unlabeled assumed-unit target range")
        let original = climate()
        let partial = HaStateReading(entityID: original.entityID,
            json: original.json.replacingOccurrences(of: #""target_temp_high":12"#, with: #""target_temp_high":null"#),
            checkedAt: observed)
        XCTAssertNil(thermostatFocusedContent(
            thermostatPresentation(context(room: partial)), accessibility: false).target)
        let accessibility = thermostatFocusedContent(thermostatPresentation(context()), accessibility: true)
        XCTAssertNil(accessibility.target)
        XCTAssertEqual(accessibility.context?.entityID, "sensor.context")
        XCTAssertEqual(accessibility.room.value, .number(-2.5))
    }

    func testFocusedRecoveryAndOperationUseTypedFactsInsteadOfFormattedMessages() {
        let original = thermostatEnvelope(context())
        for (recovery, title) in [(ThermostatRecovery.authentication, "Sign in"),
                                  (.sharedStoreUnavailable, "Unavailable"),
                                  (.readingsNotSaved, "Not saved"), (.selectionChanged, "Changed")] {
            var evidence = original.evidence; evidence.recovery = recovery
            let focused = thermostatFocusedContent(
                ThermostatLiveEnvelope(evidence: evidence, now: observed).presentation, accessibility: false)
            XCTAssertEqual(focused.recoveryTitle, title)
            XCTAssertEqual(focused.room.value, .number(-2.5))
            XCTAssertEqual(focused.room.checkedAt, observed)
            XCTAssertEqual(focused.roomAttribution, "Last known")
        }
        let pending = ClimateOperation(entityID: "climate.room", action: "heatUp", startedAt: observed)
        XCTAssertEqual(thermostatFocusedContent(
            thermostatPresentation(context(operation: pending)), accessibility: false).recoveryTitle, "Updating")
        let failed = ClimateOperation(entityID: "climate.room", action: "heatUp",
            startedAt: observed, error: "Applied")
        XCTAssertEqual(thermostatFocusedContent(
            thermostatPresentation(context(operation: failed)), accessibility: false).recoveryTitle, "Update failed")
        let unavailable = thermostatFocusedContent(
            thermostatPresentation(context(room: climate(mode: "unavailable"))), accessibility: false)
        XCTAssertEqual(unavailable.roomAttribution, "Unavailable")
        XCTAssertNil(unavailable.room.value)
    }

    func testFocusedFooterDistinguishesInertExamplesFromSavedOrUnavailableRoutes() {
        let presentation = thermostatPresentation(context())
        XCTAssertEqual(thermostatFocusedContent(presentation, accessibility: false,
            destination: .inert).footerLabel, "Open · inactive")
        for destination in [ThermostatDestination.ticket(UUID()), .unavailable] {
            XCTAssertEqual(thermostatFocusedContent(presentation, accessibility: false,
                destination: destination).footerLabel, "Open")
        }
    }

    func testFocusedRangeShorthandRequiresOrderedDistinctEndpoints() {
        let original = climate()
        for (low, high) in [(12.0, 7.0), (7.0, 7.0), (19.96, 20.04), (-0.04, 0.04)] {
            let record = HaStateReading(entityID: original.entityID,
                json: original.json.replacingOccurrences(of: #""target_temp_low":7"#, with: #""target_temp_low":\#(low)"#)
                    .replacingOccurrences(of: #""target_temp_high":12"#, with: #""target_temp_high":\#(high)"#),
                checkedAt: observed)
            let presentation = thermostatPresentation(context(room: record))
            XCTAssertNil(thermostatFocusedContent(presentation, accessibility: false).target)
            XCTAssertEqual(thermostatTargetFacts(presentation).map(\.value), [Double(low), Double(high)])
        }
    }

    func testFocusedSummaryPrecisionDoesNotChangeRawEvidenceOrAccessibility() {
        let original = climate("-2.56")
        let record = HaStateReading(entityID: original.entityID,
            json: original.json.replacingOccurrences(of: #""target_temp_low":7"#, with: #""target_temp_low":7.126"#)
                .replacingOccurrences(of: #""target_temp_high":12"#, with: #""target_temp_high":12.764"#),
            checkedAt: observed)
        let presentation = thermostatPresentation(context(room: record))
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(thermostatFocusedNumberText(presentation.room, summary: true, locale: locale), "-2.6")
        XCTAssertEqual(thermostatFocusedNumberText(presentation.room, summary: false, locale: locale), "-2.56")
        XCTAssertEqual(thermostatFocusedContent(presentation, accessibility: false).target, "7.1–12.8 °C")
        XCTAssertEqual(presentation.room.value, .number(-2.56))
        XCTAssertEqual(thermostatTargetFacts(presentation).map(\.value), [7.126, 12.764])
        let zero = thermostatPresentation(context(room: climate("0"))).room
        XCTAssertEqual(thermostatFocusedNumberText(zero, summary: true, locale: locale), "0")
        let tiny = thermostatPresentation(context(room: climate("-0.04"))).room
        XCTAssertEqual(thermostatFocusedNumberText(tiny, summary: true, locale: locale), "0")
        let absent = thermostatPresentation(context(room: climate("null"))).room
        XCTAssertNil(thermostatFocusedNumberText(absent, summary: true, locale: locale))
        for (unit, want) in [("°C", "1.2"), ("°F", "1.2"), ("K", "1.2"), ("lux", "1.23")] {
            var sensor = presentation.sensors[0]
            sensor.name = "Outside temperature"; sensor.value = .number(1.23456); sensor.reportedUnit = unit
            XCTAssertEqual(thermostatFocusedNumberText(sensor, summary: true, locale: locale), want)
            XCTAssertEqual(thermostatFocusedNumberText(sensor, summary: false, locale: locale), "1.23456")
        }
        var smallSensor = presentation.sensors[0]
        smallSensor.value = .number(0.000123456); smallSensor.reportedUnit = "mV"
        XCTAssertEqual(thermostatFocusedNumberText(smallSensor, summary: true, locale: locale), "0.000123")
        smallSensor.reportedUnit = nil
        XCTAssertEqual(thermostatFocusedNumberText(smallSensor, summary: true, locale: locale), "0.000123")
        XCTAssertEqual(thermostatFocusedNumberText(presentation.room, summary: true,
            locale: Locale(identifier: "de_DE")), "-2,6")
    }

    func testFocusedAccessibilityUsesVisiblePrimaryHistoryAndFullRawPrecision() {
        var signedOut = config; signedOut.token = ""
        let presentation = thermostatPresentation(HaStoreSnapshot(config: signedOut, scope: "scope",
            readings: context(room: climate("-2.56123")).readings, thermostatSelectionRevision: generation))
        let focused = thermostatFocusedContent(presentation, accessibility: true)
        XCTAssertEqual(presentation.room.availability, .current)
        XCTAssertEqual(focused.roomAttribution, "Last known")
        let primary = thermostatFocusedReadingAccessibility(focused.room, attribution: focused.roomAttribution,
            locale: Locale(identifier: "en_US"))
        XCTAssertTrue(primary.contains("Last known"))
        XCTAssertTrue(primary.contains("-2.56123 °C"))
        XCTAssertTrue(primary.contains("checked"))
        let context = thermostatFocusedReadingAccessibility(presentation.sensors[0])
        XCTAssertFalse(context.localizedCaseInsensitiveContains("last known"))
        XCTAssertEqual(presentation.sensors[0].availability, .current)
    }

    func testFocusedFiniteExtremeHeatCoolTargetsNeverBecomeInfinityDuringSummaryRounding() throws {
        for mode in ["heat", "cool"] {
            let original = climate(mode: mode)
            let record = HaStateReading(entityID: original.entityID,
                json: original.json.replacingOccurrences(of: #""current_humidity":54"#,
                    with: #""current_humidity":54,"temperature":1e308"#), checkedAt: observed)
            let presentation = thermostatPresentation(context(room: record))
            XCTAssertEqual(presentation.state?.target, 1e308)
            XCTAssertEqual(thermostatTargetFacts(presentation).first?.value, 1e308)
            let text = try XCTUnwrap(thermostatFocusedContent(presentation, accessibility: false).target)
            XCTAssertFalse(text.contains("∞"), mode)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("infinity"), mode)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("nan"), mode)
        }
    }
}
