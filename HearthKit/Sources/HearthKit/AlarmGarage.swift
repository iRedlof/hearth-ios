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

    public init(entityID: String, name: String, state: String, since: String? = nil, open: Bool? = nil,
                moving: Bool = false, action: DoorAction? = nil, stale: Bool = false, error: String? = nil,
                supportsStop: Bool? = nil, pending: Bool = false, actionRevision: String = "",
                replacingOperation: String = "") {
        self.entityID = entityID; self.name = name; self.state = state; self.since = since
        self.open = open; self.moving = moving; self.action = action; self.stale = stale; self.error = error
        self.supportsStop = supportsStop; self.pending = pending
        self.actionRevision = actionRevision; self.replacingOperation = replacingOperation
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

/// The garage row for one reading. `error` is the read's own failure (or an old cache); a reading
/// that is not this garage is a failure too. A failure never offers a button, and a missing or
/// failed reading never becomes a guessed state.
public func alarmGarageRow(entityID: String, reading: HaStateReading?, error: String?, now: Date,
                           zone: TimeZone = .current, locale: Locale = .current) -> AlarmGarageRow {
    let door = reading.flatMap { $0.entityID == entityID ? doorFromState($0.json) : nil }
        .flatMap { $0.id == entityID && $0.kind == .garage ? $0 : nil }
    let problem = error ?? (reading != nil && door == nil ? garageUnreadableMessage : nil)
    let wording = garageWording(door?.state ?? (problem == nil ? nil : "unavailable"))
    let stale = problem != nil && wording.open != nil
    let resting = door.map { ["closed", "open"].contains($0.state) } ?? false
    let since: String? = stale
        ? sinceLabel(reading?.checkedAt, now: now, zone: zone, locale: locale)?
            .replacingOccurrences(of: GarageText.sincePrefix, with: GarageText.lastCheckedPrefix)
        : resting ? sinceLabel(door?.since, now: now, zone: zone, locale: locale) : nil
    let stopBlocked = wording.action == .stop && door?.supportsStop == false
    let name = door.flatMap { $0.name == entityID ? nil : $0.name } ?? doorFallbackName(entityID)
    return AlarmGarageRow(entityID: entityID, name: name, state: wording.word, since: since,
        open: wording.open, moving: wording.action == .stop,
        action: problem != nil || stopBlocked ? nil : wording.action,
        stale: stale, error: problem, supportsStop: door?.supportsStop)
}

/// A failed garage command stays on its row, as last known with no button, until a newer
/// successful reading replaces it (the rule the Doors card applied).
public func garageCommandError(_ operation: DoorOperation?, entityID: String,
                               readings: [String: HaStateReading], failures: [String: HaStateFailure]) -> String? {
    guard let operation, !operation.pending, operation.entityID == entityID,
          let error = operation.error else { return nil }
    if let ended = operation.endedAt, let read = readings[entityID], read.checkedAt > ended,
       failures[entityID] == nil { return nil }
    return error
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
