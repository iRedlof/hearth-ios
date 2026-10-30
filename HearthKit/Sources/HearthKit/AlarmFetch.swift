import Foundation

public struct AlarmFetchResult: Sendable {
    public let entityID: String
    public let lockID: String
    public let lockName: String
    public let readings: [String: HaStateReading]
    public let errors: [String: String]
    public let setup: Bool
    public init(entityID: String = "", lockID: String = "", lockName: String = "",
                readings: [String: HaStateReading] = [:], errors: [String: String] = [:], setup: Bool = false) {
        self.entityID = entityID; self.lockID = lockID; self.lockName = lockName
        self.readings = readings; self.errors = errors; self.setup = setup
    }
    public func snapshot(now: Date = .now, zone: TimeZone = .current,
                         locale: Locale = .current) -> AlarmSnapshot {
        func reading(_ id: String) -> HaStateReading? {
            guard let value = readings[id], value.entityID == id,
                  AlarmState.fromJson(value.json)?.entityID == id else { return nil }
            return value
        }
        func error(_ id: String, reading: HaStateReading?) -> String? {
            if let message = errors[id] { return message }
            if readings[id] != nil && reading == nil { return "Couldn't read security data" }
            if let reading {
                let age = now.timeIntervalSince(reading.checkedAt)
                if age > 15 * 60 || age < -60 { return "Last known · Refresh to check" }
            }
            return nil
        }
        let panel = reading(entityID), door = reading(lockID)
        let alarm = panel.flatMap { AlarmState.fromJson($0.json) }
        let lock = door.flatMap { AlarmState.fromJson($0.json) }
        let name = panel.flatMap { friendlyName(ofStateJson: $0.json) } ?? "Home"
        let selected = lockID.hasPrefix("lock.")
        let doorName = lockName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? door.flatMap { friendlyName(ofStateJson: $0.json) } ?? "Door" : lockName
        var snapshot = alarmSnapshot(alarm: alarm, lockState: lock?.state, lockChanged: lock?.lastChanged,
            name: name, error: setup ? "Set up the alarm in Settings" : error(entityID, reading: panel),
            checkedAt: panel?.checkedAt, now: now, zone: zone, locale: locale,
            doorName: doorName, doorSelected: selected, doorError: error(lockID, reading: door),
            doorCheckedAt: door?.checkedAt)
        snapshot.entityID = entityID; snapshot.lockID = lockID
        return snapshot
    }
}

/// Panel and selected lock are independent successful readings. A failed lock never borrows
/// the panel's freshness; a successful unknown response replaces older security status.
public func fetchAlarmReadings(_ config: HaConfig?, previous: [String: HaStateReading] = [:],
                               now: Date = .now,
                               request: (@Sendable (String) async throws -> String)? = nil) async -> AlarmFetchResult {
    guard let config, config.isComplete else { return AlarmFetchResult(setup: true) }
    let ids = [config.entityId] + (config.hasLock ? [config.lockId] : [])
    let result = await fetchHaStateReadings(config, ids: ids, previous: previous, now: now) { id in
        let json: String
        if let request { json = try await request(id) }
        else { json = try await HaClient(config).stateJson(id) }
        guard let state = AlarmState.fromJson(json), state.entityID == id else {
            throw HaError("Couldn't read \(id.hasPrefix("lock.") ? "door" : "alarm") data")
        }
        return json
    }
    return AlarmFetchResult(entityID: config.entityId, lockID: config.hasLock ? config.lockId : "",
        lockName: config.lockName, readings: result.readings, errors: result.errors)
}

public func fetchAlarmSnapshot(_ config: HaConfig, now: Date = .now) async -> AlarmSnapshot {
    await fetchAlarmReadings(config, now: now).snapshot(now: now)
}
