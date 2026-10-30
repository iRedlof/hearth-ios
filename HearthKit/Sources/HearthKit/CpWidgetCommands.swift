import Foundation

public struct CpOperation: Sendable, Codable, Equatable {
    public var id: UUID
    public var command: String
    public var startedAt: Date
    public var error: String?
    public init(command: String, startedAt: Date = Date(), error: String? = nil, id: UUID = UUID()) {
        self.command = command; self.startedAt = startedAt; self.error = error; self.id = id
    }
}

public func cpApplyingOperation(_ snapshot: CpSnapshot, _ operation: CpOperation?, now: Date = Date()) -> CpSnapshot {
    guard let operation else { return snapshot }
    var value = snapshot
    if let error = operation.error { value.sub = error; return value }
    guard now.timeIntervalSince(operation.startedAt) < 120 else {
        value.sub = "No response · Refresh to check"
        return value
    }
    let label: String
    switch operation.command {
    case "accept": label = "Accepting…"
    case "snooze": label = "Snoozing…"
    case "leave": label = "Leaving…"
    case "unsnooze", "rejoin": label = "Rejoining…"
    case "stop": label = "Stopping…"
    case "join": label = "Joining…"
    case "auto": label = "Enabling Auto…"
    default: label = "Working…"
    }
    value.working = true
    value.sub = label
    value.keys = value.keys.map { $0.command == operation.command ? CpKey(command: $0.command, label: label) : $0 }
    if operation.command == "join" { value.actionLabel = label }
    return value
}

/// Widget commands share one injectable runtime with the native AppIntents.
public func cpPerformManual(_ command: CpCommand, client: CpClient, location: CpLocation?, udid: String,
                            canAct: @Sendable () async -> Bool = { true }) async throws {
    guard await canAct() else { throw CancellationError() }
    switch command {
    case .join:
        guard let location else { throw HaError("Choose a location first") }
        try await client.join(cpJoinBody(location))
    case .accept: try await client.accept()
    case .snooze(let seconds): try await client.snooze(seconds: seconds)
    case .unsnooze: try await client.unsnooze()
    case .leave: try await client.leave()
    case .stop:
        let status = try await client.userStatus()
        guard let sessionID = cpSessionId(status),
              let details = cpChargingFrom(try await client.chargingDetail(sessionId: sessionID)),
              details.canStop else { throw HaError("Open ChargePoint to manage this session") }
        guard await canAct() else { throw CancellationError() }
        try await client.stop(sessionId: sessionID, deviceId: nil, port: nil, udid: udid)
    case .still, .done:
        let status = try await client.userStatus()
        guard let token = cpOfferToken(status),
              case let .inLine(_, state, _, _, _) = cpWaitlistFrom(status, nil),
              ["CHARGING_FAULT", "DIB_PLUG_OUT"].contains(state) else {
            throw HaError("The charging question changed · Refresh to check")
        }
        guard await canAct() else { throw CancellationError() }
        try await client.answerStill(yes: command == .still, token: token, fault: state == "CHARGING_FAULT")
    default:
        throw HaError("Open ChargePoint to continue")
    }
}

/// Enabling Auto joins only when idle; queued users resume their current run.
public func cpEnableAuto(_ run: CpRun, client: CpClient, location: CpLocation, now: Int64,
                         canAct: @Sendable () async -> Bool = { true }) async throws -> CpRun {
    guard await canAct() else { throw CancellationError() }
    let status = try await client.userStatus()
    var state = ""
    let waitlist = cpWaitlistFrom(status, nil)
    if case let .inLine(_, value, _, _, _) = waitlist { state = value }
    guard cpSessionId(status) == nil && state != "CHARGING" else {
        throw HaError("Auto is finished while charging")
    }
    if state.isEmpty || state == "UNKNOWN" {
        guard await canAct() else { throw CancellationError() }
        try await client.join(cpJoinBody(location))
        return cpArmForCommand(run, .join, autoRun: true, now: now)
    }
    var allowance: Int?
    if CP_HELD.contains(state), let token = cpOfferToken(status) {
        allowance = cpSnoozesFrom(try? await client.snoozeDetail(offerToken: token))
    }
    guard await canAct() else { throw CancellationError() }
    return cpResumeRun(run, allowance, now)
}

public func cpCommandNamed(_ name: String) -> CpCommand? {
    switch name {
    case "join": .join
    case "accept": .accept
    case "snooze": .snooze(CP_AUTO_SNOOZE_SECONDS)
    case "leave": .leave
    case "unsnooze", "rejoin": .unsnooze
    case "stop": .stop
    case "still": .still
    case "done": .done
    default: nil
    }
}
