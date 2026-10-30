import Foundation

/// The Battery widget's display payload: the summary + when it was read.
public struct BatterySnapshot: Sendable, Equatable {
    public let summary: BatterySummary
    public let checkedAt: String
    public let state: TileSnapshotState
    public let error: String?
    public let observedAt: Date?
    public init(summary: BatterySummary, checkedAt: String, state: TileSnapshotState = .ready,
                error: String? = nil, observedAt: Date? = nil) {
        self.summary = summary; self.checkedAt = checkedAt; self.state = state
        self.error = error; self.observedAt = observedAt
    }
    public static let loading = BatterySnapshot(summary: batterySummary([]), checkedAt: "", state: .loading)

    public static let sample = BatterySnapshot(summary: batterySummary([
        Battery(id: "a", name: "Front Door Lock", level: 9),
        Battery(id: "b", name: "Backyard Motion", level: 24),
        Battery(id: "c", name: "Living Room Remote", level: 61),
        Battery(id: "d", name: "Garage Sensor", level: 88),
        Battery(id: "e", name: "Office Thermometer", level: 95),
    ]), checkedAt: "9:41 AM")
}

/// Only a successfully validated current collection earns a new observation timestamp.
public func fetchBatterySnapshot(_ config: HaConfig?, now: Date = Date(), previous: BatterySnapshot? = nil,
    read: (@Sendable () async throws -> String)? = nil) async -> BatterySnapshot {
    guard let config, config.carReady else {
        return mapBatterySnapshot(config, reply: .success("[]"), previous: previous, now: now)
    }
    let reply: Result<String, HaError>
    do {
        let json: String
        if let read { json = try await read() } else { json = try await HaClient(config).template(BATTERY_TEMPLATE) }
        reply = .success(json)
    } catch { reply = .failure(HaError(tileReadError(error))) }
    return mapBatterySnapshot(config, reply: reply, previous: previous, now: now)
}

public func mapBatterySnapshot(_ config: HaConfig?, reply: Result<String, HaError>,
    previous: BatterySnapshot? = nil, now: Date = Date()) -> BatterySnapshot {
    guard let config, config.carReady else {
        return BatterySnapshot(summary: batterySummary([]), checkedAt: "", state: .setup)
    }
    do {
        let batteries = try parseBatteryCollection(reply.get())
        return BatterySnapshot(summary: batterySummary(batteries), checkedAt: widgetClock(now),
                               state: batteries.isEmpty ? .empty : .ready, observedAt: now)
    } catch {
        let owned = previous.flatMap { $0.state == .ready || $0.state == .empty || $0.state == .failed ? $0 : nil }
        return BatterySnapshot(summary: owned?.summary ?? batterySummary([]),
                               checkedAt: owned?.checkedAt ?? "", state: .failed,
                               error: tileReadError(error), observedAt: owned?.observedAt)
    }
}

/// "9:41 AM" — shared short clock for the non-Beacon widget "Checked" stamps.
func widgetClock(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
}
