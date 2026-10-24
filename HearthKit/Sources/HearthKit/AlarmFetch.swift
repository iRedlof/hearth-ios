import Foundation

/// Fetches the live Alarm snapshot — the panel state plus the front-door lock (when configured) —
/// mapped to the same `AlarmSnapshot` the widget renders. Mirrors the Android `AlarmRepository`
/// read. Returns `.sample` when the alarm isn't configured yet (shows a representative preview).
public func fetchAlarmSnapshot(_ config: HaConfig, now: Date = Date()) async -> AlarmSnapshot {
    guard config.isComplete else { return .sample }   // needs https + auth + an alarm_control_panel entity
    let client = HaClient(config)
    do {
        let alarmJson = try await client.stateJson(config.entityId)
        let alarm = AlarmState.fromJson(alarmJson)
        let name = friendlyName(ofStateJson: alarmJson) ?? "Home"

        var lockState: String?
        var lockChanged: Date?
        if config.hasLock, let lockJson = try? await client.stateJson(config.lockId),
           let lock = AlarmState.fromJson(lockJson) {   // fromJson reads state + last_changed for any entity
            lockState = lock.state
            lockChanged = lock.lastChanged
        }

        return alarmSnapshot(alarm: alarm, lockState: lockState, lockChanged: lockChanged,
                             name: name, error: nil, checkedAt: now, now: now)
    } catch {
        return alarmSnapshot(alarm: nil, lockState: nil, lockChanged: nil, name: "Home",
                             error: friendlyError(error), checkedAt: now, now: now)
    }
}
