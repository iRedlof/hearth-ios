import Foundation

/// The Alarm card's second door row, the garage, already formatted. It mirrors the front-door
/// fields on `AlarmSnapshot` and carries its own door-command origin.
public struct AlarmGarageRow: Codable, Sendable, Equatable {
    public var entityID: String
    public var name: String             // the cover's friendly name, e.g. "Garage"
    public var state: String            // "Closed" / "Open" / "Opening…" / "Closing…" / "Unavailable" / "—"
    public var since: String?           // "since 9:50 AM"; "Last checked 9:41 AM" when last known
    public var open: Bool?              // false closed, true open or moving, nil unknown
    public var moving: Bool             // opening / closing, or its own command in flight
    public var action: DoorAction?      // nil: unavailable, last known, or another command owns the door
    public var stale: Bool              // a last-known state shown because the latest read failed
    public var error: String?
    public var supportsStop: Bool?      // as reported: nil is a missing feature mask
    public var pending: Bool            // this garage's own command is in flight
    public var actionRevision: String   // the door-command origin rendered with the button
    public var replacingOperation: String   // the pending Open/Close a Stop tap takes over
    public var commandNotice: String?   // "Couldn't open · try again": why its last command failed

    public init(entityID: String, name: String, state: String, since: String? = nil, open: Bool? = nil,
                moving: Bool = false, action: DoorAction? = nil, stale: Bool = false, error: String? = nil,
                supportsStop: Bool? = nil, pending: Bool = false, actionRevision: String = "",
                replacingOperation: String = "", commandNotice: String? = nil) {
        self.entityID = entityID; self.name = name; self.state = state; self.since = since
        self.open = open; self.moving = moving; self.action = action; self.stale = stale; self.error = error
        self.supportsStop = supportsStop; self.pending = pending
        self.actionRevision = actionRevision; self.replacingOperation = replacingOperation
        self.commandNotice = commandNotice
    }
}

/// This garage's last Open/Close/Stop, ended in failure and not yet replaced by a newer reading.
public struct GarageCommandFailure: Sendable, Equatable {
    public let action: DoorAction?
    public let error: String

    public init(action: DoorAction?, error: String) {
        self.action = action; self.error = error
    }
}

/// A reply that is not the selected garage/gate cover, at fetch time or from the cache.
let garageUnreadableMessage = "Couldn't read garage data"

private enum GarageText {
    static let unavailable = "Unavailable"
    static let noReading = "—"
    static let sincePrefix = "since "
    static let lastCheckedPrefix = "Last checked "
    static let separator = " · "
    static let commandFailed = "Couldn't update"
    static let signIn = "sign in"
    static let checkSettings = "check Settings"
    static let tryAgain = "try again"
    static let refresh = "refresh to check"
}

private func garageWording(_ state: String?) -> (word: String, open: Bool?, action: DoorAction?) {
    switch state {
    case "closed": ("Closed", false, .open)
    case "open": ("Open", true, .close)
    case "opening": (DoorAction.open.pending, true, .stop)
    case "closing": (DoorAction.close.pending, true, .stop)
    case nil: (GarageText.noReading, nil, nil)
    default: (GarageText.unavailable, nil, nil)
    }
}

/// The visible reason a failed command leaves in the status line: what failed, then what to do
/// about it. Sign-in and setup are told apart with the lock row's helpers.
private func garageCommandNotice(_ failure: GarageCommandFailure, readProblem: String?, canRetry: Bool) -> String {
    let errors = [failure.error, readProblem]
    let advice: String
    if errors.contains(where: beaconNeedsSignIn) {
        advice = GarageText.signIn
    } else if errors.contains(where: beaconNeedsSettings) {
        advice = GarageText.checkSettings
    } else {
        advice = canRetry ? GarageText.tryAgain : GarageText.refresh
    }
    return (failure.action?.failed ?? GarageText.commandFailed) + GarageText.separator + advice
}

/// The garage row for one reading. `error` is the read's own failure (or an old cache); a reading
/// that is not this garage is a failure too. A failed read never offers a button, and a missing or
/// failed reading never becomes a guessed state. A failed command (`commandFailure`) shows the row
/// last known with its reason, and keeps the button for a retry while the reading itself is good.
public func alarmGarageRow(entityID: String, reading: HaStateReading?, error: String?,
                           commandFailure: GarageCommandFailure? = nil, now: Date,
                           zone: TimeZone = .current, locale: Locale = .current) -> AlarmGarageRow {
    let door = reading.flatMap { $0.entityID == entityID ? doorFromState($0.json) : nil }
        .flatMap { $0.id == entityID && $0.kind == .garage ? $0 : nil }
    let readProblem = error ?? (reading != nil && door == nil ? garageUnreadableMessage : nil)
    let problem = readProblem ?? commandFailure?.error
    let wording = garageWording(door?.state ?? (problem == nil ? nil : "unavailable"))
    let stale = problem != nil && wording.open != nil
    let resting = door.map { ["closed", "open"].contains($0.state) } ?? false
    let since: String? = stale
        ? sinceLabel(reading?.checkedAt, now: now, zone: zone, locale: locale)?
            .replacingOccurrences(of: GarageText.sincePrefix, with: GarageText.lastCheckedPrefix)
        : resting ? sinceLabel(door?.since, now: now, zone: zone, locale: locale) : nil
    let stopBlocked = wording.action == .stop && door?.supportsStop == false
    let needsSetup = beaconNeedsSettings(commandFailure?.error)
    let action = readProblem != nil || stopBlocked || needsSetup ? nil : wording.action
    let name = door.flatMap { $0.name == entityID ? nil : $0.name } ?? doorFallbackName(entityID)
    return AlarmGarageRow(entityID: entityID, name: name, state: wording.word, since: since,
        open: wording.open, moving: wording.action == .stop, action: action,
        stale: stale, error: problem, supportsStop: door?.supportsStop,
        commandNotice: commandFailure.map {
            garageCommandNotice($0, readProblem: readProblem, canRetry: action != nil)
        })
}

/// A failed garage command stays on its row, as last known, until a newer successful reading
/// replaces it (the rule the Doors card applied).
public func garageCommandFailure(_ operation: DoorOperation?, entityID: String, readings: [String: HaStateReading],
                                 failures: [String: HaStateFailure]) -> GarageCommandFailure? {
    guard let operation, !operation.pending, operation.entityID == entityID,
          let error = operation.error else { return nil }
    if let ended = operation.endedAt, let read = readings[entityID], read.checkedAt > ended,
       failures[entityID] == nil { return nil }
    return GarageCommandFailure(action: DoorAction(rawValue: operation.action), error: error)
}

/// Binds the garage button to the door-command origin and shows a command in flight. Stop takes
/// over only this garage's own unfinished Open/Close; while any other door command is pending the
/// button is inert, as the store accepts one door command at a time.
public func alarmApplyingDoorOperation(_ snapshot: AlarmSnapshot, _ operation: DoorOperation?,
                                       actionRevision: String) -> AlarmSnapshot {
    guard var garage = snapshot.garage else { return snapshot }
    garage.actionRevision = actionRevision
    if let operation, operation.pending, let action = DoorAction(rawValue: operation.action) {
        if operation.entityID == garage.entityID {
            let stoppable = [DoorAction.open, .close].contains(action) && garage.supportsStop != false
            garage.pending = true
            garage.moving = true
            garage.state = action.pending
            garage.since = nil
            garage.action = stoppable ? .stop : nil
            garage.replacingOperation = stoppable ? operation.id : ""
        } else {
            garage.action = nil
        }
    }
    var result = snapshot
    result.garage = garage
    return result
}

/// A compact door row's one-line status, longest first; the view shows the first that fits, so a
/// narrow card drops "since", then the time, and never cuts the state word.
public func alarmDoorStatusLines(state: String, since: String?, stale: Bool) -> [String] {
    guard let since, !since.isEmpty else { return [state] }
    let prefix = stale ? GarageText.lastCheckedPrefix : GarageText.sincePrefix
    let time = since.hasPrefix(prefix) ? String(since.dropFirst(prefix.count)) : since
    let lines = (stale ? [] : [state + GarageText.separator + since]) + [state + GarageText.separator + time, state]
    var seen = Set<String>()
    return lines.filter { seen.insert($0).inserted }
}

/// The garage row's one-line status, longest first. A failed command's reason takes the line
/// ("Couldn't open · try again", else "Couldn't open") until a newer reading or a retry.
public func alarmGarageStatusLines(_ garage: AlarmGarageRow) -> [String] {
    guard let notice = garage.commandNotice, !garage.pending else {
        return alarmDoorStatusLines(state: garage.state, since: garage.since, stale: garage.stale)
    }
    let short = notice.components(separatedBy: GarageText.separator).first ?? notice
    return notice == short ? [notice] : [notice, short]
}
