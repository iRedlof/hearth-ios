import Foundation

/// The Lights widget's payload.
public struct LightsSnapshot: Sendable, Equatable {
    public let summary: LightsSummary; public let checkedAt: String
    public init(summary: LightsSummary, checkedAt: String) { self.summary = summary; self.checkedAt = checkedAt }

    public static let sample = LightsSnapshot(summary: lightsSummary([
        Light(id: "light.kitchen", name: "Kitchen", on: true, percent: 80, since: nil, rgb: 0xFFFF_D27F),
        Light(id: "light.living", name: "Living Room", on: true, percent: 45, since: nil, rgb: 0xFF7F_B0FF),
        Light(id: "light.desk", name: "Desk Lamp", on: true, percent: 100, since: nil, rgb: nil),
        Light(id: "light.porch", name: "Porch", on: false, percent: nil, since: nil, rgb: nil),
        Light(id: "light.hall", name: "Hallway", on: false, percent: nil, since: nil, rgb: nil),
    ], now: Date(), pinned: ["light.porch"]), checkedAt: "9:41 AM")
}

/// Live lights via `LIGHTS_TEMPLATE`, with the "always show" pinned set from config.
public func fetchLightsSnapshot(_ config: HaConfig, now: Date = Date()) async -> LightsSnapshot {
    let checked = widgetClock(now)
    guard config.baseUrl.hasPrefix("https://"), config.hasAuth else { return .sample }
    do {
        let json = try await HaClient(config).template(LIGHTS_TEMPLATE)
        return LightsSnapshot(summary: lightsSummary(lightsFromTemplate(json), now: now, pinned: config.lightPins),
                              checkedAt: checked)
    } catch {
        return LightsSnapshot(summary: LightsSummary(headline: "Can't reach HA", on: [], pinned: [],
                                                     onCount: 0, offCount: 0, off: []), checkedAt: checked)
    }
}
