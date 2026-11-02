import Foundation

public enum ThermostatForegroundLoadCause: Sendable, Equatable { case initialOrConfig, cacheChanged, chargepointSignIn, dashboardRefresh, thermostatRefresh }
public enum ThermostatReadSource: Sendable, Equatable { case dashboardRefresh, glyphRefresh, routeRefresh, commandSettlement }
public struct ThermostatReadOwner: Sendable, Equatable {
    public let id: UUID
    public let source: ThermostatReadSource
    public init(id: UUID = UUID(), source: ThermostatReadSource) { self.id = id; self.source = source }
}
public struct ThermostatRefreshRequest: Sendable, Equatable {
    public let id: UUID
    public let selection: ThermostatSelectionOrigin
    public init(id: UUID = UUID(), selection: ThermostatSelectionOrigin) { self.id = id; self.selection = selection }
}
/// One request's lifetime can be revoked across Sendable transport callbacks. It is not a registry.
public final class ThermostatRequestLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    public init() {}
    public func isActive() -> Bool { lock.withLock { active } }
    public func invalidate() { lock.withLock { active = false } }
}
public func thermostatOriginBinding(_ origin: ThermostatSelectionOrigin?) -> String {
    guard let origin, let data = try? JSONEncoder().encode(origin), data.count <= 16 * 1024 else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
}
public func thermostatOrigin(from binding: String) -> ThermostatSelectionOrigin? {
    guard let data = binding.data(using: .utf8), data.count <= 16 * 1024,
          let origin = try? JSONDecoder().decode(ThermostatSelectionOrigin.self, from: data),
          UUID(uuidString: origin.selectionRevision) != nil, !origin.scope.isEmpty,
          origin.entityID.hasPrefix("climate.") else { return nil }
    return origin
}
public enum ThermostatDestination: Sendable, Equatable { case ticket(UUID), unavailable, inert }
public struct ClimateControlOrigin: Sendable, Equatable {
    public let selection: ThermostatSelectionOrigin
    public let revision: String
    public let observedMode: String?
    public init?(context: HaStoreSnapshot, expectedSelection: ThermostatSelectionOrigin) {
        let envelope = thermostatEnvelope(context)
        guard expectedSelection.matches(context), envelope.presentation.authorityAvailable,
              !context.climateRevision.isEmpty else { return nil }
        selection = expectedSelection; revision = context.climateRevision
        observedMode = envelope.presentation.state?.mode
    }
}
public enum ThermostatTargetKind: Sendable, Hashable {
    case heat, cool, temperature, lowerEndpoint, upperEndpoint
    public var title: String {
        switch self {
        case .heat: "Heat to"
        case .cool: "Cool to"
        case .temperature: "Target temperature"
        case .lowerEndpoint: "Lower endpoint"
        case .upperEndpoint: "Upper endpoint"
        }
    }
}
/// Saved target facts are independent of the ability to send a command.
public struct ThermostatTargetFact: Sendable, Equatable {
    public let kind: ThermostatTargetKind
    public let value: Double?
    public let reportedUnit: String?
    public func valueText(locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return "Not reported" }
        let number = value.formatted(.number.precision(.significantDigits(1...17)).grouping(.never).locale(locale))
        return number + (reportedUnit.map { " \($0)" } ?? "")
    }
}
public func thermostatTargetFacts(_ presentation: ThermostatPresentation) -> [ThermostatTargetFact] {
    guard let state = presentation.state else { return [] }
    let unit = presentation.room.reportedUnit
    if state.isRange {
        return [.init(kind: .heat, value: state.low, reportedUnit: unit),
                .init(kind: .cool, value: state.high, reportedUnit: unit)]
    }
    switch state.mode {
    case "heat": return [.init(kind: .heat, value: state.target, reportedUnit: unit)]
    case "cool": return [.init(kind: .cool, value: state.target, reportedUnit: unit)]
    default:
        return state.target.map { [.init(kind: .temperature, value: $0, reportedUnit: unit)] } ?? []
    }
}
/// Non-active range attributes remain readable, but never supply a directional control target.
public func thermostatOtherReportedTargets(_ presentation: ThermostatPresentation) -> [ThermostatTargetFact] {
    guard let state = presentation.state, !state.isRange, state.low != nil || state.high != nil else { return [] }
    return [.init(kind: .lowerEndpoint, value: state.low, reportedUnit: presentation.room.reportedUnit),
            .init(kind: .upperEndpoint, value: state.high, reportedUnit: presentation.room.reportedUnit)]
}
public enum ThermostatTicketError: Error { case invalid, oversized, duplicate }
public struct ThermostatTicket: Codable, Sendable, Equatable, Identifiable {
    public let version: Int
    public let id: UUID
    public let issuedAt, expiresAt: Date
    public let evidence: ThermostatRawEvidence
    public init(evidence: ThermostatRawEvidence, issuedAt: Date = .now, id: UUID = UUID()) throws {
        version = 1; self.id = id; self.issuedAt = issuedAt
        expiresAt = issuedAt.addingTimeInterval(48 * 3600); self.evidence = evidence
        try validate()
    }
    private enum CodingKeys: String, CodingKey { case version, id, issuedAt, expiresAt, evidence }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version); id = try values.decode(UUID.self, forKey: .id)
        issuedAt = try values.decode(Date.self, forKey: .issuedAt); expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        evidence = try values.decode(ThermostatRawEvidence.self, forKey: .evidence)
        try validate()
    }
    private func validate() throws {
        guard version == 1, issuedAt.timeIntervalSince1970.isFinite, expiresAt.timeIntervalSince1970.isFinite,
              expiresAt.timeIntervalSince(issuedAt) == 48 * 3600 else { throw ThermostatTicketError.invalid }
        if let origin = evidence.origin {
            guard !origin.scope.isEmpty, UUID(uuidString: origin.selectionRevision) != nil,
                  origin.entityID == evidence.entityID, origin.resumeID == evidence.resumeID,
                  origin.selectedSensorIDs == evidence.selectedSensorIDs else { throw ThermostatTicketError.invalid }
        }
        let allowed = Set([evidence.entityID] + evidence.fetchedSensorIDs)
        for (id, reading) in evidence.readings {
            guard !id.isEmpty, allowed.contains(id), id == reading.entityID,
                  reading.checkedAt.timeIntervalSince1970.isFinite, reading.checkedAt <= issuedAt,
                  let data = reading.json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let state = object["state"] as? String, !state.isEmpty,
                  object["entity_id"] == nil || object["entity_id"] as? String == id else { throw ThermostatTicketError.invalid }
        }
        for (id, failure) in evidence.failures {
            guard !id.isEmpty, allowed.contains(id), failure.checkedAt.timeIntervalSince1970.isFinite,
                  failure.checkedAt <= issuedAt else { throw ThermostatTicketError.invalid }
        }
        if let operation = evidence.operation {
            guard operation.entityID == evidence.entityID, !operation.id.isEmpty,
                  operation.startedAt.timeIntervalSince1970.isFinite, operation.startedAt <= issuedAt else {
                throw ThermostatTicketError.invalid
            }
        }
    }
}
public struct ThermostatEntryPayload: Sendable {
    public let date: Date
    public let envelope: ThermostatLiveEnvelope
    public let destination: ThermostatDestination
    public var snapshot: ThermostatSnapshot { envelope.snapshot }
    public var presentation: ThermostatPresentation { envelope.presentation }
    public init(date: Date, envelope: ThermostatLiveEnvelope, destination: ThermostatDestination) {
        self.date = date; self.envelope = envelope; self.destination = destination
    }
}
public func thermostatSavedObservation(_ presentation: ThermostatPresentation) -> Date? {
    presentation.room.checkedAt.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil }
}
public func thermostatObservationText(_ date: Date, locale: Locale = .current, zone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale; formatter.timeZone = zone
    formatter.dateStyle = .medium; formatter.timeStyle = .medium
    return formatter.string(from: date)
}
public enum ThermostatRoutePurpose: Sendable, Equatable { case readings, mode }
public func thermostatReadingsURL(for destination: ThermostatDestination,
                                 purpose: ThermostatRoutePurpose = .readings) -> URL? {
    let host = purpose == .mode ? "thermostat-mode" : "thermostat-readings"
    switch destination {
    case .ticket(let id): return URL(string: "hearth://\(host)/\(id.uuidString)")
    case .unavailable:
        return purpose == .readings ? URL(string: "hearth://thermostat-readings/unavailable") : nil
    case .inert: return nil
    }
}
public func thermostatDestination(from url: URL) -> ThermostatDestination? {
    thermostatRoute(from: url)?.destination
}
public func thermostatRoute(from url: URL) -> ThermostatRouteRequest? {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          parts.scheme == "hearth", (parts.host == "thermostat-readings" || parts.host == "thermostat-mode"),
          parts.user == nil, parts.password == nil, parts.port == nil,
          parts.query == nil, parts.fragment == nil, !parts.percentEncodedPath.contains("%") else { return nil }
    let purpose: ThermostatRoutePurpose = parts.host == "thermostat-mode" ? .mode : .readings
    let path = parts.path
    if path == "/unavailable", purpose == .readings { return ThermostatRouteRequest(destination: .unavailable) }
    guard path.first == "/", let id = UUID(uuidString: String(path.dropFirst())),
          path == "/" + id.uuidString || path == "/" + id.uuidString.lowercased() else { return nil }
    return ThermostatRouteRequest(destination: .ticket(id), purpose: purpose)
}
public func bindThermostatEntry(_ envelope: ThermostatLiveEnvelope, date: Date = .now,
                               persist: (ThermostatTicket) throws -> Void) -> ThermostatEntryPayload {
    do {
        let ticket = try ThermostatTicket(evidence: envelope.evidence, issuedAt: date)
        try persist(ticket)
        return ThermostatEntryPayload(date: date, envelope: envelope, destination: .ticket(ticket.id))
    } catch {
        var evidence = envelope.evidence; evidence.recovery = .readingsNotSaved
        return ThermostatEntryPayload(date: date, envelope: ThermostatLiveEnvelope(evidence: evidence, now: date),
            destination: .unavailable)
    }
}
public struct ThermostatRouteRequest: Sendable, Equatable {
    public let eventID: UUID
    public let destination: ThermostatDestination
    public let purpose: ThermostatRoutePurpose
    public init(destination: ThermostatDestination, eventID: UUID = UUID(),
                purpose: ThermostatRoutePurpose = .readings) {
        self.destination = destination; self.eventID = eventID; self.purpose = purpose
    }
}
public struct ThermostatRouteAdmission: Sendable {
    public private(set) var active: ThermostatRouteRequest?
    public init() {}
    public mutating func admit(_ destination: ThermostatDestination,
                              purpose: ThermostatRoutePurpose = .readings) -> ThermostatRouteRequest? {
        guard destination != .inert else { return nil }
        if purpose == .mode, destination == .unavailable { return nil }
        if let active, active.destination == destination, active.purpose == purpose { return active }
        let request = ThermostatRouteRequest(destination: destination, purpose: purpose); active = request; return request
    }
    public mutating func close() { active = nil }
    public mutating func returning(_ original: ThermostatRouteRequest, replacing eventID: UUID?) -> ThermostatRouteRequest? {
        guard active?.eventID == eventID else { return nil }
        active = nil
        return admit(original.destination, purpose: original.purpose)
    }
}
public enum ThermostatRouteStatus: Sendable, Equatable { case current, selectionChanged, expired, unavailable, sharedStoreUnavailable }
public struct ThermostatRefreshClaim: Sendable, Equatable {
    public let requestID, taskID: UUID
    public let selection: ThermostatSelectionOrigin
}
public struct ThermostatRouteSession: Sendable {
    public let openingTicket: ThermostatTicket
    public private(set) var shownEnvelope: ThermostatLiveEnvelope
    public private(set) var status: ThermostatRouteStatus = .current
    public private(set) var controlOrigin: ClimateControlOrigin?
    public private(set) var refreshClaim: ThermostatRefreshClaim?
    public var pickerID: UUID?
    private var active = true
    private var initialPurposeConsumed = false
    public init(ticket: ThermostatTicket, context: HaStoreSnapshot?, now: Date = .now) {
        openingTicket = ticket; shownEnvelope = ThermostatLiveEnvelope(evidence: ticket.evidence, now: now)
        reconcile(context: context, now: now)
    }
    /// Navigation consumes its presentation request once; it cannot read remotely or dispatch.
    public mutating func consumeInitialModePresentation(_ purpose: ThermostatRoutePurpose) -> Bool {
        guard !initialPurposeConsumed else { return false }
        initialPurposeConsumed = true
        let opening = ThermostatLiveEnvelope(evidence: openingTicket.evidence).presentation
        guard purpose == .mode, active, status == .current, let controlOrigin,
              controlOrigin.revision == openingTicket.evidence.commandRevision,
              opening.authorityAvailable, thermostatModeChoiceAvailable(opening) else { return false }
        return thermostatModeChoiceAvailable(shownEnvelope.presentation)
    }
    public mutating func reconcile(context: HaStoreSnapshot?, now: Date = .now) {
        guard active else { return }
        guard status != .selectionChanged, status != .expired else { return }
        guard now.timeIntervalSince1970.isFinite, now < openingTicket.expiresAt else {
            retire(.expired); return
        }
        guard let origin = openingTicket.evidence.origin,
              openingTicket.evidence.recovery != .selectionChanged else { retire(.selectionChanged); return }
        guard let context else { retire(.sharedStoreUnavailable); return }
        guard origin.matches(context) else { retire(.selectionChanged); return }
        status = .current
        if ![.readingsNotSaved, .operationNotSaved].contains(shownEnvelope.evidence.recovery) {
            shownEnvelope = thermostatEnvelope(context, now: now)
        }
        controlOrigin = shownEnvelope.presentation.authorityAvailable
            ? ClimateControlOrigin(context: context, expectedSelection: origin) : nil
    }
    private mutating func retire(_ status: ThermostatRouteStatus) {
        self.status = status; controlOrigin = nil; refreshClaim = nil; pickerID = nil
        var evidence = shownEnvelope.evidence
        evidence.recovery = status == .sharedStoreUnavailable ? .sharedStoreUnavailable : .selectionChanged
        shownEnvelope = ThermostatLiveEnvelope(evidence: evidence)
    }
    public mutating func beginRefresh(requestID: UUID, taskID: UUID, context: HaStoreSnapshot?, now: Date = .now) -> ThermostatRefreshClaim? {
        reconcile(context: context, now: now)
        guard active, status == .current, refreshClaim == nil,
              context?.climateOperation?.pending != true,
              let selection = openingTicket.evidence.origin else { return nil }
        let claim = ThermostatRefreshClaim(requestID: requestID, taskID: taskID, selection: selection)
        refreshClaim = claim; return claim
    }
    public mutating func finishRefresh(claim: ThermostatRefreshClaim, envelope: ThermostatLiveEnvelope,
                                       context: HaStoreSnapshot?, now: Date = .now) -> Bool {
        guard active, refreshClaim == claim else { return false }
        reconcile(context: context, now: now)
        guard status == .current, refreshClaim == claim else { return false }
        refreshClaim = nil
        guard envelope.evidence.origin == claim.selection else {
            retire(.sharedStoreUnavailable); return false
        }
        shownEnvelope = envelope
        if envelope.evidence.recovery == .selectionChanged { retire(.selectionChanged); return false }
        controlOrigin = envelope.presentation.authorityAvailable
            ? context.flatMap { ClimateControlOrigin(context: $0, expectedSelection: claim.selection) } : nil
        return true
    }
    public mutating func close() { active = false; controlOrigin = nil; refreshClaim = nil; pickerID = nil }
    public mutating func recordOperationSaveFailure(context: HaStoreSnapshot?, now: Date = .now) {
        guard active, status == .current, let origin = openingTicket.evidence.origin,
              let context, origin.matches(context) else { return }
        var evidence = shownEnvelope.evidence
        evidence.commandRevision = context.climateRevision; evidence.operation = context.climateOperation
        evidence.recovery = .operationNotSaved
        shownEnvelope = ThermostatLiveEnvelope(evidence: evidence, now: now)
        controlOrigin = nil; pickerID = nil
    }
}
