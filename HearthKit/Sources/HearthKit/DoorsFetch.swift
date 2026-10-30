import Foundation

public struct DoorsSnapshot: Sendable, Equatable {
    public let summary: DoorsSummary; public let checkedAt: String
    public let state: TileSnapshotState; public let error: String?
    public let observedAt: Date?; public let doors: [Door]
    public var actionScope: String?; public var actionRevision: String?; public var operation: DoorOperation?
    public init(summary: DoorsSummary, checkedAt: String, state: TileSnapshotState = .ready,
                error: String? = nil, observedAt: Date? = nil, doors: [Door] = [],
                actionScope: String? = nil, actionRevision: String? = nil, operation: DoorOperation? = nil) {
        self.summary = summary; self.checkedAt = checkedAt; self.state = state
        self.error = error; self.observedAt = observedAt; self.doors = doors
        self.actionScope = actionScope; self.actionRevision = actionRevision; self.operation = operation
    }

    public static let loading = DoorsSnapshot(summary: DoorsSummary(headline: "Loading doors…",
        tone: .unknown, lockLine: nil, rows: []), checkedAt: "", state: .loading)

    public static let sample = DoorsSnapshot(summary: doorsSummary([
        Door(id: "cover.garage", name: "Garage", kind: .garage, state: "open", since: Date().addingTimeInterval(-600)),
        Door(id: "lock.front", name: "Front Door", kind: .lock, state: "locked", since: nil),
        Door(id: "binary_sensor.back", name: "Back Door", kind: .sensor, state: "off", since: nil),
        Door(id: "cover.gate", name: "Side Gate", kind: .garage, state: "closed", since: nil),
    ], now: Date()), checkedAt: "9:41 AM")
}

/// Cache failures stay attached to their selected row; only validated new replies advance its time.
public func fetchDoorsSnapshot(_ config: HaConfig?, previous: [String: HaStateReading] = [:],
    now: Date = Date(), request: (@Sendable (String) async throws -> String)? = nil) async -> DoorsSnapshot {
    guard let config, config.carReady else {
        return mapDoorsSnapshot(config: config, readings: [:], errors: [:], now: now)
    }
    let ids = doorsSelectedIDs(config)
    let client = HaClient(config)
    var readings: [String: HaStateReading] = [:]
    var errors: [String: String] = [:]
    for id in ids {
        do {
            try Task.checkCancellation()
            let json: String
            if let request { json = try await request(id) }
            else { json = try await client.stateJson(id) }
            guard let door = doorFromState(json), door.id == id else {
                throw HaError("Unexpected entity reading")
            }
            readings[id] = HaStateReading(entityID: id, json: json, checkedAt: now)
        } catch {
            readings[id] = previous[id].flatMap { $0.entityID == id ? $0 : nil }
            errors[id] = error is CancellationError ? "Refresh interrupted" : tileReadError(error)
        }
    }
    return mapDoorsSnapshot(config: config, readings: readings, errors: errors, now: now)
}

/// Use the oldest represented successful observation, including failed row history, so a partial
/// refresh cannot advertise a freshly observed complete collection.
public func mapDoorsSnapshot(config: HaConfig?, readings: [String: HaStateReading],
    errors: [String: String], now: Date, collectionError: String? = nil) -> DoorsSnapshot {
    guard let config, config.carReady else {
        return DoorsSnapshot(summary: DoorsSummary(headline: "Set up Home Assistant",
            tone: .unknown, lockLine: nil, rows: []), checkedAt: "", state: .setup)
    }
    let ids = doorsSelectedIDs(config)
    guard !ids.isEmpty else {
        if let error = collectionError, !error.isEmpty {
            return DoorsSnapshot(summary: DoorsSummary(headline: "No reading", tone: .unknown,
                lockLine: nil, rows: []), checkedAt: "", state: .failed, error: error)
        }
        return DoorsSnapshot(summary: doorsSummary([], now: now), checkedAt: "",
                             state: config.doorsChosen ? .empty : .choose)
    }
    let doors = ids.map { id -> Door in
        let reading = readings[id]
        let parsed = reading.flatMap { $0.entityID == id ? doorFromState($0.json) : nil }
            .flatMap { $0.id == id ? $0 : nil }
        let error = errors[id].flatMap { $0.isEmpty ? nil : $0 }
            ?? (reading == nil ? "No reading" : parsed == nil ? "Unexpected entity reading" : nil)
        if let parsed {
            return Door(id: id, name: parsed.name, kind: parsed.kind, state: parsed.state, since: parsed.since,
                        checkedAt: reading?.checkedAt, error: error, supportsStop: parsed.supportsStop)
        }
        return Door(id: id, name: doorFallbackName(id), kind: doorKindForID(id) ?? .sensor,
                    state: "unknown", since: nil, error: error)
    }
    let observedAt = doors.compactMap(\.checkedAt).min()
    let successful = doors.contains { $0.checkedAt != nil && $0.error == nil }
    let hasResult = ids.contains { readings[$0] != nil || errors[$0] != nil }
    return DoorsSnapshot(summary: doorsSummary(doors, now: now),
        checkedAt: observedAt.map(widgetClock) ?? "",
        state: successful ? .ready : hasResult ? .failed : .loading,
        error: hasResult ? doors.compactMap(\.error).first : nil, observedAt: observedAt, doors: doors)
}
