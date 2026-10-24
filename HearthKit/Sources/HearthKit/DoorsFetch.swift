import Foundation

public struct DoorsSnapshot: Sendable, Equatable {
    public let summary: DoorsSummary; public let checkedAt: String
    public init(summary: DoorsSummary, checkedAt: String) { self.summary = summary; self.checkedAt = checkedAt }

    public static let sample = DoorsSnapshot(summary: doorsSummary([
        Door(id: "cover.garage", name: "Garage", kind: .garage, state: "open", since: Date().addingTimeInterval(-600)),
        Door(id: "lock.front", name: "Front Door", kind: .lock, state: "locked", since: nil),
        Door(id: "binary_sensor.back", name: "Back Door", kind: .sensor, state: "off", since: nil),
        Door(id: "cover.gate", name: "Side Gate", kind: .garage, state: "closed", since: nil),
    ], now: Date()), checkedAt: "9:41 AM")
}

/// The configured doors (covers/sensors + the front-door lock) read from HA, open-first.
public func fetchDoorsSnapshot(_ config: HaConfig, now: Date = Date()) async -> DoorsSnapshot {
    let checked = widgetClock(now)
    var ids = config.doorIds
    if !config.lockId.isEmpty && !ids.contains(config.lockId) { ids.append(config.lockId) }
    guard config.baseUrl.hasPrefix("https://"), config.hasAuth, !ids.isEmpty else { return .sample }
    let client = HaClient(config)
    var doors: [Door] = []
    for id in ids {
        if let json = try? await client.stateJson(id), let door = doorFromState(json) { doors.append(door) }
    }
    return DoorsSnapshot(summary: doorsSummary(doors, now: now), checkedAt: checked)
}
