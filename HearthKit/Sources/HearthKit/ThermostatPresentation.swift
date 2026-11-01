import Foundation

/// The selected readings have a lifetime separate from the revision of an individual command.
public struct ThermostatSelectionOrigin: Codable, Equatable, Sendable {
    public let scope, selectionRevision, entityID, resumeID: String
    public let selectedSensorIDs: [String]
    public init?(_ context: HaStoreSnapshot) {
        guard !context.scope.isEmpty, let revision = context.thermostatSelectionRevision,
              UUID(uuidString: revision) != nil else { return nil }
        scope = context.scope; selectionRevision = revision
        entityID = context.config?.climateId ?? ""; resumeID = context.config?.resumeId ?? ""
        selectedSensorIDs = context.config?.sensorIds ?? []
    }
    public func matches(_ context: HaStoreSnapshot) -> Bool { self == Self(context) }
}
public enum ThermostatConfiguration: String, Codable, Equatable, Sendable {
    case unconfigured, needsAuthentication, invalid, ready, unavailable
}
public enum ThermostatRecovery: String, Codable, Equatable, Sendable {
    case none, setup, authentication, readFailed, sharedStoreUnavailable
    case readingsNotSaved, selectionChanged, operationNotSaved
}
public enum ThermostatReadingAvailability: String, Equatable, Sendable {
    case current, lastKnown, unavailable, noReading
}
public enum ThermostatReadingSource: String, Equatable, Sendable {
    case homeAssistantClimate, homeAssistantSensor
}
public enum ThermostatReadingValue: Equatable, Sendable {
    case number(Double), text(String)
}
public enum ThermostatOperationFacet: Equatable, Sendable {
    case none, pending(ClimateOperation), failed(ClimateOperation)
}
public struct ThermostatReadingFacet: Equatable, Sendable {
    public var entityID: String
    public var name: String
    public var source: ThermostatReadingSource
    public var value: ThermostatReadingValue?
    public var reportedUnit: String?
    public var availability: ThermostatReadingAvailability
    public var checkedAt: Date?
    public var lastChanged: Date?
    public var failure: HaStateFailure?
}
public struct ThermostatRawEvidence: Codable, Equatable, Sendable {
    public var origin: ThermostatSelectionOrigin?
    public var configuration: ThermostatConfiguration
    public var commandRevision: String
    public var readings: [String: HaStateReading]
    public var failures: [String: HaStateFailure]
    public var operation: ClimateOperation?
    public var recovery: ThermostatRecovery
    public var entityID: String = ""
    public var resumeID: String = ""
    public var selectedSensorIDs: [String] = []
    public var fetchedSensorIDs: [String] {
        var seen = Set<String>()
        return Array(selectedSensorIDs.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(3))
    }
}
public struct ThermostatPresentation: Equatable, Sendable {
    public var origin: ThermostatSelectionOrigin?
    public var configuration: ThermostatConfiguration
    public var state: ClimateState?
    public var room: ThermostatReadingFacet
    public var humidity: Double?
    public var sensors: [ThermostatReadingFacet]
    public var recovery: ThermostatRecovery
    public var operation: ThermostatOperationFacet
    public var authorityAvailable: Bool
    public var selectedSensorIDs: [String] = []
    public var unfetchedSensorIDs: [String] {
        let fetched = Set(sensors.map(\.entityID))
        var seen = Set<String>()
        return selectedSensorIDs.filter { !$0.isEmpty && !fetched.contains($0) && seen.insert($0).inserted }
    }
}

private func thermostatRoomIsHistorical(_ presentation: ThermostatPresentation) -> Bool {
    presentation.room.availability == .lastKnown
        || (presentation.room.value != nil && presentation.recovery != .none)
}

/// The focused card consumes typed observations; commands and typography belong to its host.
public struct ThermostatFocusedContent: Equatable, Sendable {
    public let room: ThermostatReadingFacet
    public let roomAttribution: String
    public let context: ThermostatReadingFacet?
    public let mode: String
    public let target: String?
    public let recoveryTitle: String?
    public let tone: BeaconTone
    public let footerLabel: String
}
/// Card temperatures use nearest-tenth summaries; other numeric sensors retain three significant
/// digits. Raw accessibility and the destination retain up to seventeen significant digits.
public func thermostatFocusedNumberText(_ reading: ThermostatReadingFacet, summary: Bool,
                                        locale: Locale = .current) -> String? {
    guard case let .number(number) = reading.value else { return nil }
    if summary {
        if reading.source == .homeAssistantClimate || ["°C", "°F", "K"].contains(reading.reportedUnit ?? "") {
            return thermostatSummaryTemperature(number)
                .formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
        }
        return number.formatted(.number.precision(.significantDigits(1...3)).grouping(.never).locale(locale))
    }
    return number.formatted(.number.precision(.significantDigits(1...17)).grouping(.never).locale(locale))
}
private func thermostatSummaryTemperature(_ number: Double) -> Double {
    let scaled = number * 10
    guard scaled.isFinite else { return number }
    let rounded = scaled.rounded() / 10
    return rounded == 0 ? 0 : rounded
}
public func thermostatFocusedReadingAccessibility(_ reading: ThermostatReadingFacet, attribution: String? = nil,
                                                   locale: Locale = .current) -> String {
    let value: String
    switch reading.value {
    case .number:
        value = (thermostatFocusedNumberText(reading, summary: false, locale: locale) ?? "No reading")
            + (reading.reportedUnit.map { " \($0)" } ?? " · Unit not reported")
    case .text(let text): value = text
    case nil: value = reading.availability == .unavailable ? "Unavailable" : "No reading"
    }
    let availability = attribution.map { ", \($0)" }
        ?? (reading.availability == .lastKnown ? ", Last known" : "")
    let time = reading.checkedAt.map { ", checked \(thermostatObservationText($0, locale: locale))" }
        ?? ", no saved observation"
    return "\(reading.name), \(value)\(availability)\(time)"
}
public func thermostatFocusedContent(_ presentation: ThermostatPresentation,
                                     accessibility: Bool,
                                     destination: ThermostatDestination = .inert) -> ThermostatFocusedContent {
    let recoveryTitle: String?
    switch presentation.recovery {
    case .authentication: recoveryTitle = "Sign in"
    case .setup: recoveryTitle = "Set up"
    case .sharedStoreUnavailable: recoveryTitle = "Unavailable"
    case .readingsNotSaved, .operationNotSaved: recoveryTitle = "Not saved"
    case .selectionChanged: recoveryTitle = "Changed"
    case .readFailed:
        recoveryTitle = presentation.room.failure?.reason == .transport ? "Can't connect" : "Check failed"
    case .none:
        switch presentation.operation {
        case .pending: recoveryTitle = "Updating"
        case .failed: recoveryTitle = "Update failed"
        case .none: recoveryTitle = nil
        }
    }
    let historical = thermostatRoomIsHistorical(presentation)
    let attribution: String
    if historical { attribution = "Last known" }
    else {
        switch presentation.room.availability {
        case .current: attribution = "Room"
        case .lastKnown: attribution = "Last known"
        case .unavailable: attribution = "Unavailable"
        case .noReading: attribution = "No reading"
        }
    }
    let state = presentation.state
    let mode = state.map { state in
        CLIMATE_MODES.first(where: { $0.mode == state.mode })?.name
            ?? (state.mode == "auto" ? "Auto" : state.mode.replacingOccurrences(of: "_", with: " ").capitalizedFirst)
    } ?? "Mode not reported"
    let target: String?
    if !accessibility, presentation.recovery == .none, state?.isAvailable == true,
       let unit = presentation.room.reportedUnit, let state {
        func number(_ value: Double) -> String {
            thermostatSummaryTemperature(value)
                .formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        }
        if state.isRange, let low = state.low, let high = state.high, low < high,
           thermostatSummaryTemperature(low) < thermostatSummaryTemperature(high) {
            target = "\(number(low))–\(number(high)) \(unit)"
        } else if !state.isRange, ["heat", "cool"].contains(state.mode), let value = state.target {
            target = "\(number(value)) \(unit)"
        } else { target = nil }
    } else { target = nil }
    return ThermostatFocusedContent(room: presentation.room, roomAttribution: attribution,
        context: presentation.sensors.first, mode: mode, target: target, recoveryTitle: recoveryTitle,
        tone: beaconClimatePair(state?.mode, stale: historical || presentation.room.value == nil
            || state?.isAvailable != true),
        footerLabel: destination == .inert ? "Open · inactive" : "Open")
}

public struct ThermostatLiveEnvelope: Equatable, Sendable {
    public let evidence: ThermostatRawEvidence
    public let presentation: ThermostatPresentation
    public let snapshot: ThermostatSnapshot
    public init(evidence: ThermostatRawEvidence, now: Date = .now,
                zone: TimeZone = .current, locale: Locale = .current) {
        self.evidence = evidence
        presentation = thermostatPresentation(evidence)
        var value = ThermostatFetchResult(entityID: evidence.entityID, sensorIDs: evidence.fetchedSensorIDs,
            readings: evidence.readings, errors: evidence.failures.mapValues(\.message),
            setup: evidence.configuration == .unconfigured,
            resumeID: evidence.resumeID).snapshot(now: now, zone: zone, locale: locale)
        value.requestScope = evidence.origin?.scope ?? ""
        value.climateRevision = evidence.commandRevision
        value = climateApplyingOperation(value, evidence.operation)
        value.needsSignIn = presentation.recovery == .authentication
        value.needsSettings = [.unconfigured, .invalid].contains(evidence.configuration)
            || value.needsSignIn
            || presentation.room.failure?.reason == .entityNotFound
        switch presentation.recovery {
        case .sharedStoreUnavailable:
            value.setup = false; value.status = "Can't read settings"
            value.error = "Shared storage is unavailable. Please reopen Hearth."
        case .readingsNotSaved:
            value.error = "Can't save readings · Refresh to retry"
            value.status = "Check failed"
        case .selectionChanged:
            value.error = "Configuration changed · Refresh to check"
            value.status = "Details changed"
        case .operationNotSaved:
            value.error = "Can't save update · Refresh to check"
            value.status = "Check failed"
        case .authentication:
            value.setup = false; value.status = "Sign in again"
        case .readFailed:
            value.status = presentation.room.failure?.reason == .transport ? "Can't connect"
                : value.needsSettings ? "Check setup" : "Check failed"
        case .setup:
            if evidence.configuration == .invalid { value.setup = false; value.status = "Check setup" }
        case .none:
            if evidence.configuration == .ready, presentation.room.checkedAt == nil, presentation.state == nil {
                value.status = "No saved reading"
            }
        }
        let historical = thermostatRoomIsHistorical(presentation)
        if case let .number(number) = presentation.room.value {
            value.roomTemp = degrees(number)
            value.roomSub = historical ? "Last known" : "In the room"
        } else {
            value.roomTemp = "—"; value.roomSub = "No reading"
        }
        value.stale = historical || presentation.room.failure != nil
            || [.sharedStoreUnavailable, .readingsNotSaved, .selectionChanged, .operationNotSaved].contains(presentation.recovery)
        if historical { value.tone = .offline }
        for index in value.sensors.indices {
            let facet = presentation.sensors[index]
            value.sensors[index].stale = facet.availability == .lastKnown || facet.failure != nil
        }
        if !presentation.authorityAvailable {
            value.canAdjustHeatUp = false; value.canAdjustHeatDown = false
            value.canAdjustCoolUp = false; value.canAdjustCoolDown = false
            value.canPickMode = false; value.canPickFan = false; value.canResume = false
        }
        value.evidence = evidence
        snapshot = value
    }
}

public func thermostatPresentation(_ context: HaStoreSnapshot,
                                   recovery: ThermostatRecovery = .none) -> ThermostatPresentation {
    thermostatEnvelope(context, recovery: recovery).presentation
}
public func thermostatEnvelope(_ context: HaStoreSnapshot, now: Date = .now,
                               recovery: ThermostatRecovery = .none) -> ThermostatLiveEnvelope {
    let config = context.config
    let configuration: ThermostatConfiguration
    if config == nil || config?.climateId.isEmpty == true { configuration = .unconfigured }
    else if let config, !config.climateId.hasPrefix("climate.") || !config.baseUrl.hasPrefix("https://") {
        configuration = .invalid
    } else if config?.hasAuth != true { configuration = .needsAuthentication }
    else { configuration = .ready }
    var evidence = ThermostatRawEvidence(origin: ThermostatSelectionOrigin(context), configuration: configuration,
        commandRevision: context.climateRevision, readings: [:], failures: [:],
        operation: context.climateOperation, recovery: recovery)
    evidence.entityID = config?.climateId ?? ""; evidence.resumeID = config?.resumeId ?? ""
    evidence.selectedSensorIDs = config?.sensorIds ?? []
    let ids = Set(([evidence.entityID] + evidence.fetchedSensorIDs).filter { !$0.isEmpty })
    evidence.readings = context.readings.filter { ids.contains($0.key) && $0.key == $0.value.entityID }
    evidence.failures = context.failures.filter { ids.contains($0.key) }
    return ThermostatLiveEnvelope(evidence: evidence, now: now)
}
public func thermostatStorageUnavailableEnvelope(now: Date = .now) -> ThermostatLiveEnvelope {
    ThermostatLiveEnvelope(evidence: ThermostatRawEvidence(origin: nil, configuration: .unavailable,
        commandRevision: "", readings: [:], failures: [:], operation: nil,
        recovery: .sharedStoreUnavailable), now: now)
}

private func thermostatPresentation(_ evidence: ThermostatRawEvidence) -> ThermostatPresentation {
    var recovery = evidence.recovery
    if recovery == .none {
        if evidence.configuration == .needsAuthentication { recovery = .authentication }
        else if [.unconfigured, .invalid].contains(evidence.configuration) { recovery = .setup }
        else if let failure = evidence.failures[evidence.entityID] {
            recovery = failure.reason == .authentication ? .authentication : .readFailed
        }
    }
    let retained = [.sharedStoreUnavailable, .readingsNotSaved, .selectionChanged, .operationNotSaved].contains(recovery)
    let room = thermostatFacet(id: evidence.entityID, source: .homeAssistantClimate,
        reading: evidence.readings[evidence.entityID], failure: evidence.failures[evidence.entityID], retained: retained)
    let sensors = evidence.fetchedSensorIDs.map {
        thermostatFacet(id: $0, source: .homeAssistantSensor, reading: evidence.readings[$0],
            failure: evidence.failures[$0], retained: retained)
    }
    let state = validThermostatObject(evidence.readings[evidence.entityID], id: evidence.entityID)
        .flatMap { _ in evidence.readings[evidence.entityID].flatMap { ClimateState.fromJson($0.json) } }
    let operation: ThermostatOperationFacet = evidence.operation.map { $0.pending ? .pending($0) : .failed($0) } ?? .none
    let bound = evidence.origin.map {
        $0.entityID == evidence.entityID && $0.resumeID == evidence.resumeID
            && $0.selectedSensorIDs == evidence.selectedSensorIDs
    } ?? false
    return ThermostatPresentation(origin: evidence.origin, configuration: evidence.configuration, state: state,
        room: room, humidity: state.flatMap { state in
            guard let humidity = climateNumber(state.humidity), humidity >= 0, humidity <= 100 else { return nil }
            return humidity
        }, sensors: sensors, recovery: recovery,
        operation: operation, authorityAvailable: bound && evidence.configuration == .ready && recovery == .none
            && state?.isAvailable == true && evidence.operation?.pending != true,
        selectedSensorIDs: evidence.selectedSensorIDs)
}

private func validThermostatObject(_ reading: HaStateReading?, id: String) -> [String: Any]? {
    guard let reading, reading.entityID == id, reading.checkedAt.timeIntervalSinceReferenceDate.isFinite,
          let data = reading.json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let state = object["state"] as? String, !state.isEmpty,
          object["entity_id"] == nil || object["entity_id"] as? String == id else { return nil }
    return object
}
private func thermostatFacet(id: String, source: ThermostatReadingSource, reading: HaStateReading?,
                             failure: HaStateFailure?, retained: Bool) -> ThermostatReadingFacet {
    let object = validThermostatObject(reading, id: id)
    let attrs = object?["attributes"] as? [String: Any]
    let fallback = source == .homeAssistantClimate ? "Thermostat"
        : id.split(separator: ".").last.map(String.init)?.replacingOccurrences(of: "_", with: " ").capitalizedFirst ?? "Sensor"
    func string(_ key: String) -> String? {
        guard let value = attrs?[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
        return value
    }
    let stateText = object?["state"] as? String
    let unavailable = ["unknown", "unavailable"].contains(stateText?.lowercased() ?? "")
    let value: ThermostatReadingValue?
    if unavailable { value = nil }
    else if source == .homeAssistantClimate {
        value = reading.flatMap { ClimateState.fromJson($0.json) }.flatMap { climateNumber($0.current) }.map { .number($0) }
    } else if let stateText, let number = Double(stateText) {
        value = climateNumber(number).map { .number($0) }
    } else if let stateText, !["", "null"].contains(stateText.lowercased()) { value = .text(stateText) }
    else { value = nil }
    let availability: ThermostatReadingAvailability = unavailable ? .unavailable : value == nil ? .noReading
        : failure != nil || retained ? .lastKnown : .current
    return ThermostatReadingFacet(entityID: id, name: string("friendly_name") ?? fallback, source: source,
        value: object == nil ? nil : value, reportedUnit: string(source == .homeAssistantClimate ? "temperature_unit" : "unit_of_measurement"),
        availability: object == nil ? .noReading : availability,
        checkedAt: object == nil ? nil : reading?.checkedAt,
        lastChanged: parseOffsetDateTime(object?["last_changed"] as? String), failure: failure)
}
