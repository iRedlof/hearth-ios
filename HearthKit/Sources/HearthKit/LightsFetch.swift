import Foundation

/// The Lights widget's payload.
public struct LightsSnapshot: Sendable, Equatable {
    public let summary: LightsSummary; public let checkedAt: String
    public let state: TileSnapshotState; public let error: String?
    public init(summary: LightsSummary, checkedAt: String, state: TileSnapshotState = .ready, error: String? = nil) {
        self.summary = summary; self.checkedAt = checkedAt; self.state = state; self.error = error
    }
    public static let loading = LightsSnapshot(summary: lightsSummary([], now: .now), checkedAt: "", state: .loading)

    public static let sample = LightsSnapshot(summary: lightsSummary([
        Light(id: "light.kitchen", name: "Kitchen", on: true, percent: 80, since: nil, rgb: 0xFFFF_D27F),
        Light(id: "light.living", name: "Living Room", on: true, percent: 45, since: nil, rgb: 0xFF7F_B0FF),
        Light(id: "light.desk", name: "Desk Lamp", on: true, percent: 100, since: nil, rgb: nil),
        Light(id: "light.porch", name: "Porch", on: false, percent: nil, since: nil, rgb: nil),
        Light(id: "light.hall", name: "Hallway", on: false, percent: nil, since: nil, rgb: nil),
    ], now: Date(), pinned: ["light.porch"]), checkedAt: "9:41 AM")
}

/// Live lights via `LIGHTS_TEMPLATE`, with the "always show" pinned set from config. A failed read
/// keeps the lights of `previous` as last known.
public func fetchLightsSnapshot(_ config: HaConfig?, now: Date = Date(), previous: LightsSnapshot? = nil,
    read: (@Sendable () async throws -> String)? = nil) async -> LightsSnapshot {
    guard let config, config.carReady else { return mapLightsSnapshot(config, reply: .success("[]"), now: now) }
    let reply: Result<String, HaError>
    do {
        let json: String
        if let read { json = try await read() } else { json = try await HaClient(config).template(LIGHTS_TEMPLATE) }
        reply = .success(json)
    } catch { reply = .failure(HaError(tileReadError(error))) }
    return mapLightsSnapshot(config, reply: reply, previous: previous, now: now)
}

/// The rows of a lights reading: an array of `light.*` rows, each in a state Hearth knows.
private func lightsReadingRows(_ json: String) throws -> [[String: Any]] {
    let states = ["on", "off", "unknown", "unavailable"]
    guard let data = json.data(using: .utf8),
          let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          rows.allSatisfy({ ($0["entity_id"] as? String)?.hasPrefix("light.") == true &&
              states.contains($0["state"] as? String ?? "") }) else {
        throw HaError("Unexpected lights reading")
    }
    return rows
}

/// Throws unless `json` is a well-formed lights reading. Only a reading that passes may be saved
/// as last known.
public func validateLightsReading(_ json: String) throws {
    _ = try lightsReadingRows(json)
}

/// A successful reply is the lights as they are now. A failed one keeps the lights `previous`
/// knew, by name, as last known: none of them reporting, so none can be toggled or read as on/off.
public func mapLightsSnapshot(_ config: HaConfig?, reply: Result<String, HaError>,
    previous: LightsSnapshot? = nil, now: Date = Date()) -> LightsSnapshot {
    guard let config, config.carReady else {
        return LightsSnapshot(summary: lightsSummary([], now: now), checkedAt: "", state: .setup)
    }
    do {
        let json = try reply.get()
        let rows = try lightsReadingRows(json)
        return LightsSnapshot(summary: lightsSummary(lightsFromTemplate(json), now: now, pinned: config.lightPins),
                              checkedAt: widgetClock(now), state: rows.isEmpty ? .empty : .ready)
    } catch {
        return LightsSnapshot(summary: lightsSummary(lightsLastKnown(previous), now: now, pinned: config.lightPins),
                              checkedAt: "", state: .failed, error: tileReadError(error))
    }
}

/// Every light a snapshot that was read (or was itself last known) names, none of them reporting.
/// A snapshot that never held a reading (not set up, still loading) knows no lights.
func lightsLastKnown(_ previous: LightsSnapshot?) -> [Light] {
    guard let previous, [.ready, .empty, .failed].contains(previous.state) else { return [] }
    let summary = previous.summary
    return (summary.on + summary.pinned + summary.off).map {
        Light(id: $0.id, name: $0.name, on: false, percent: nil, since: nil, available: false)
    }
}
