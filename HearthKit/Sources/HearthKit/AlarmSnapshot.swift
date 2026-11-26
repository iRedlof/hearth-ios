import Foundation

/// Everything the Alarm Beacon view renders, already formatted (mirrors CarSnapshot's style).
public struct AlarmSnapshot: Codable, Sendable, Equatable {
    public var name: String          // the home's name, e.g. "Home"
    public var checkedAt: String     // "7:17 PM"
    public var stateWord: String     // "Disarmed" / "Armed home" / "Alarm triggered"
    public var detail: String        // "Disarmed at 7:00 AM" (always shown, v1.4.26)
    public var tone: BeaconTone      // rail/panel tone
    public var glyph: AlarmGlyph     // shield glyph: off / home / lock / alert
    public var doorName: String      // "Front Door"
    public var doorState: String     // "Locked" / "Unlocked" / "—"
    public var doorSince: String?    // "since 7:44 PM"
    public var doorLocked: Bool?     // true locked, false not secure, nil unknown/in-transit
    public var actions: [AlarmAction]
    public var actionSlots: [AlarmAction]
    public var entityID = ""
    public var lockID = ""
    public var requestScope = ""
    public var alarmRevision = ""
    public var setup = false
    public var error: String?
    public var stale = false
    public var doorSelected = true
    public var doorStale = false
    public var doorError: String?
    public var doorAction: LockAction?
    public var needsSettings = false
    public var needsSignIn = false
    public var commandPending = false
    public var commandFeedback: String?
    public var commandError: String?
    // Original typed facts and independent observation dates; Small never parses display copy.
    public var panelRawState: String?
    public var doorRawState: String?
    public var panelObservedAt: Date?
    public var doorObservedAt: Date?
    public var panelChangedAt: Date?
    public var doorChangedAt: Date?
    public var storageUnavailable = false
    public var operation: AlarmOperation?

    public init(name: String, checkedAt: String, stateWord: String, detail: String, tone: BeaconTone,
                glyph: AlarmGlyph, doorName: String, doorState: String, doorSince: String?,
                doorLocked: Bool?, actions: [AlarmAction]) {
        self.name = name; self.checkedAt = checkedAt; self.stateWord = stateWord; self.detail = detail
        self.tone = tone; self.glyph = glyph; self.doorName = doorName; self.doorState = doorState
        self.doorSince = doorSince; self.doorLocked = doorLocked; self.actions = actions
        self.actionSlots = actions
        self.doorAction = doorLocked.map { $0 ? .unlock : .lock }
    }

    public static let sample: AlarmSnapshot = {
        var snapshot = AlarmSnapshot(
        name: "Home", checkedAt: "7:17 PM", stateWord: "Disarmed", detail: "Disarmed at 7:00 AM",
        tone: .blue, glyph: .off, doorName: "Front Door", doorState: "Locked",
        doorSince: "since 7:44 PM", doorLocked: true, actions: [.armHome, .armAway])
        snapshot.panelRawState = "disarmed"; snapshot.doorRawState = "locked"
        return snapshot
    }()
}
