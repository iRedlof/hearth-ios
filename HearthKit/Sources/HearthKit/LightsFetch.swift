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

/// Live lights via `LIGHTS_TEMPLATE`, with the "always show" pinned set from config.
public func fetchLightsSnapshot(_ config: HaConfig?, now: Date = Date(),
    read: (@Sendable () async throws -> String)? = nil) async -> LightsSnapshot {
    guard let config, config.carReady else { return mapLightsSnapshot(config, reply: .success("[]"), now: now) }
    let reply: Result<String, HaError>
    do {
        let json: String
        if let read { json = try await read() } else { json = try await HaClient(config).template(LIGHTS_TEMPLATE) }
        reply = .success(json)
    } catch { reply = .failure(HaError(tileReadError(error))) }
    return mapLightsSnapshot(config, reply: reply, now: now)
}

public func mapLightsSnapshot(_ config: HaConfig?, reply: Result<String, HaError>,
    now: Date = Date()) -> LightsSnapshot {
    let checked = widgetClock(now)
    guard let config, config.carReady else {
        return LightsSnapshot(summary: lightsSummary([], now: now), checkedAt: "", state: .setup)
    }
    do {
        let json = try reply.get()
        guard let data = json.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.allSatisfy({ ($0["entity_id"] as? String)?.hasPrefix("light.") == true &&
                  ["on", "off", "unknown", "unavailable"].contains($0["state"] as? String ?? "") }) else {
            throw HaError("Unexpected lights reading")
        }
        return LightsSnapshot(summary: lightsSummary(lightsFromTemplate(json), now: now, pinned: config.lightPins),
                              checkedAt: checked, state: rows.isEmpty ? .empty : .ready)
    } catch {
        return LightsSnapshot(summary: lightsSummary([], now: now), checkedAt: "",
                              state: .failed, error: tileReadError(error))
    }
}
