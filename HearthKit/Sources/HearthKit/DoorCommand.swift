import Foundation
import CoreFoundation

/// `delivered` means dispatch was durably claimed, not that Home Assistant confirmed the target.
public struct DoorOperation: Codable, Sendable, Equatable {
    public var id: String
    public var entityID: String
    public var action: String
    public var startedAt: Date
    public var endedAt: Date?
    public var error: String?
    public var delivered: Bool
    public var actionRevision: String?
    public var pending: Bool { endedAt == nil }

    public init(id: String = UUID().uuidString, entityID: String, action: String, startedAt: Date,
                endedAt: Date? = nil, error: String? = nil, delivered: Bool = false, actionRevision: String? = nil) {
        self.id = id; self.entityID = entityID; self.action = action; self.startedAt = startedAt
        self.endedAt = endedAt; self.error = error; self.delivered = delivered
        self.actionRevision = actionRevision
    }
}

public struct DoorCommand: Sendable, Equatable {
    public let domain: String
    public let service: String
    public let entityID: String
    public let action: DoorAction

    public init(domain: String, service: String, entityID: String, action: DoorAction) {
        self.domain = domain; self.service = service; self.entityID = entityID; self.action = action
    }
}

public enum DoorActionResult: Sendable, Equatable { case confirmed, obsolete, rejected, unconfirmed }

/// A command observation must have a matching envelope/raw entity and a recent successful time.
public func doorCommandObservation(_ reading: HaStateReading, entityID: String,
                                   now: Date) -> Door? {
    validatedDoorObservation(reading, entityID: entityID, now: now, allowUnknownGarageState: false)
}

private func validatedDoorObservation(_ reading: HaStateReading, entityID: String, now: Date,
                                      allowUnknownGarageState: Bool) -> Door? {
    let age = now.timeIntervalSince(reading.checkedAt)
    guard age.isFinite, age >= 0, age <= 15 * 60,
          reading.entityID == entityID, let door = doorFromState(reading.json), door.id == entityID,
          door.kind == .garage || door.kind == .lock else { return nil }
    if ["unknown", "unavailable"].contains(door.state) {
        guard allowUnknownGarageState && door.kind == .garage else { return nil }
    }
    return door
}

private func doorTarget(entityID: String, action: String) -> DoorCommand? {
    guard let action = DoorAction(rawValue: action), let kind = doorKindForID(entityID),
          (kind == .garage && action != .lock) || (kind == .lock && action == .lock) else { return nil }
    return DoorCommand(domain: action.service.domain, service: action.service.service,
                       entityID: entityID, action: action)
}

public func doorCommand(_ reading: HaStateReading, entityID: String, action: String,
                        now: Date) -> DoorCommand? {
    validatedDoorCommand(reading, entityID: entityID, action: action, now: now, ownedStopTakeover: false)
}

private func validatedDoorCommand(_ reading: HaStateReading, entityID: String, action: String,
                                  now: Date, ownedStopTakeover: Bool) -> DoorCommand? {
    guard let command = doorTarget(entityID: entityID, action: action),
          let door = validatedDoorObservation(reading, entityID: entityID, now: now,
            allowUnknownGarageState: ownedStopTakeover && command.action == .stop) else { return nil }
    let compatible: Bool
    switch command.action {
    case .open: compatible = door.state == "closed"
    case .close: compatible = door.state == "open"
    case .stop: compatible = ["closed", "open", "opening", "closing"].contains(door.state)
        || (ownedStopTakeover && ["unknown", "unavailable"].contains(door.state))
    case .lock: compatible = ["unlocked", "open"].contains(door.state)
    }
    guard compatible else { return nil }
    if door.kind == .garage,
       let data = reading.json.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let attributes = object["attributes"] as? [String: Any],
       let raw = attributes["supported_features"] {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value < Double(Int.max),
              value.rounded(.towardZero) == value else { return nil }
        let bit = command.action == .open ? 1 : command.action == .close ? 2 : 8
        guard Int(value) & bit != 0 else { return nil }
    }
    return command
}

/// `ownedStopTakeover` is set only after the store accepts the exact rendered replacement UUID.
/// It permits unknown garage preflight telemetry, while every confirmation still needs known state.
@discardableResult
public func executeDoorAction(entityID: String, action: String,
                              ownedStopTakeover: Bool = false,
                              isCurrent: @Sendable () -> Bool,
                              claimDispatch: @Sendable () throws -> Bool,
                              read: @Sendable () async throws -> HaStateReading,
                              send: @Sendable (DoorCommand) async throws -> Void,
                              observe: @Sendable (HaStateReading) async throws -> Void = { _ in },
                              wait: @Sendable () async throws -> Void,
                              now: @Sendable () -> Date = { .now },
                              confirmationAttempts: Int = 10) async throws -> DoorActionResult {
    guard let target = doorTarget(entityID: entityID, action: action) else { return .rejected }
    guard isCurrent() else { return .obsolete }
    try Task.checkCancellation()
    let initial = try await read()
    guard isCurrent() else { return .obsolete }
    let stopTakeover = ownedStopTakeover && target.action == .stop
    guard let door = validatedDoorObservation(initial, entityID: entityID, now: now(),
        allowUnknownGarageState: stopTakeover) else {
        throw HaError("Couldn't read the selected door")
    }
    try await observe(initial)
    try Task.checkCancellation()
    guard isCurrent() else { return .obsolete }
    // Stop must still cancel an earlier command that was posted but has not begun moving.
    if target.action != .stop && target.action.done(door.state) { return .confirmed }
    guard let command = validatedDoorCommand(initial, entityID: entityID, action: action,
        now: now(), ownedStopTakeover: stopTakeover) else { return .rejected }
    guard try claimDispatch() else { return .obsolete }
    let dispatchedAt = now()
    try Task.checkCancellation()
    guard isCurrent() else { return .obsolete }
    try await send(command)
    for _ in 0..<max(0, confirmationAttempts) {
        try Task.checkCancellation()
        guard isCurrent() else { return .obsolete }
        try await wait()
        try Task.checkCancellation()
        guard isCurrent() else { return .obsolete }
        let reading = try await read()
        guard isCurrent() else { return .obsolete }
        guard reading.checkedAt >= dispatchedAt,
              let observed = doorCommandObservation(reading, entityID: entityID, now: now()) else {
            throw HaError("Couldn't confirm the selected door")
        }
        try await observe(reading)
        try Task.checkCancellation()
        guard isCurrent() else { return .obsolete }
        if command.action.done(observed.state) { return .confirmed }
    }
    return .unconfirmed
}
