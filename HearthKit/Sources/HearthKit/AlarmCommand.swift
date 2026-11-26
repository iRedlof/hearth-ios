import Foundation

public struct AlarmCommand: Sendable, Equatable {
    public let domain: String
    public let service: String
    public let entityID: String
    public let target: String
}

private func alarmTarget(entityID: String, action: String) -> AlarmCommand? {
    if entityID.hasPrefix("alarm_control_panel."), entityID.count > "alarm_control_panel.".count,
       let action = AlarmAction(rawValue: action) {
        return AlarmCommand(domain: "alarm_control_panel", service: action.service,
            entityID: entityID, target: action.target)
    }
    if entityID.hasPrefix("lock."), entityID.count > "lock.".count, let action = LockAction(rawValue: action) {
        return AlarmCommand(domain: "lock", service: action.service, entityID: entityID, target: action.target)
    }
    return nil
}

/// A response's envelope and raw entity identity must both match the rendered command target.
public func alarmObservation(_ reading: HaStateReading, entityID: String) -> AlarmState? {
    guard reading.entityID == entityID, let state = AlarmState.fromJson(reading.json),
          state.entityID == entityID else { return nil }
    return state
}

/// Capability checks apply to arming modes; basic lock/unlock and disarm have no feature bit.
/// HA's server-side default code is deliberately left to HA rather than guessed from code_format.
public func alarmCommand(_ reading: HaStateReading, entityID: String, action: String) -> AlarmCommand? {
    guard let command = alarmTarget(entityID: entityID, action: action),
          let state = alarmObservation(reading, entityID: entityID) else { return nil }
    if command.domain == "alarm_control_panel" {
        guard let action = AlarmAction(rawValue: action), alarmAvailableActions(state).contains(action) else { return nil }
    } else {
        guard lockActionFor(state.state)?.rawValue == action else { return nil }
    }
    return command
}

public enum AlarmActionResult: Sendable, Equatable { case confirmed, obsolete, rejected, unconfirmed }

/// Reads live state, posts at most once, then observes the bound entity until its exact target.
/// Transition states and HTTP acknowledgement never stand in for confirmed security telemetry.
@discardableResult
public func executeAlarmAction(entityID: String, action: String,
                              isCurrent: @Sendable () -> Bool,
                              read: @Sendable () async throws -> HaStateReading,
                              send: @Sendable (AlarmCommand) async throws -> Void,
                              observe: @Sendable (HaStateReading) async throws -> Void = { _ in },
                              wait: @Sendable () async throws -> Void,
                              confirmationAttempts: Int = 10) async throws -> AlarmActionResult {
    guard let target = alarmTarget(entityID: entityID, action: action) else { return .rejected }
    guard isCurrent() else { return .obsolete }
    try Task.checkCancellation()
    let initial = try await read()
    guard isCurrent() else { return .obsolete }
    guard let state = alarmObservation(initial, entityID: entityID) else { throw HaError("Couldn't read the selected device") }
    try await observe(initial)
    try Task.checkCancellation()
    guard isCurrent() else { return .obsolete }
    if state.state == target.target { return .confirmed }
    guard let command = alarmCommand(initial, entityID: entityID, action: action) else { return .rejected }
    try await send(command)
    for _ in 0..<max(0, confirmationAttempts) {
        try Task.checkCancellation()
        guard isCurrent() else { return .obsolete }
        try await wait()
        try Task.checkCancellation()
        guard isCurrent() else { return .obsolete }
        let reading = try await read()
        guard isCurrent() else { return .obsolete }
        guard let observed = alarmObservation(reading, entityID: entityID) else { throw HaError("Couldn't read the selected device") }
        try await observe(reading)
        guard isCurrent() else { return .obsolete }
        if observed.state == command.target { return .confirmed }
    }
    return .unconfirmed
}
