import Foundation

/// One labelled stat row shown on the ChargePoint right panel while charging (Est. distance / Time / Charger).
public struct CpStat: Sendable, Equatable, Codable {
    public let label: String
    public let value: String
    public init(label: String, value: String) { self.label = label; self.value = value }
}

/// Everything the ChargePoint Beacon view renders, already formatted (mirrors the other snapshots).
/// ChargePoint's rail is a FIXED brand orange (`.orange`), unlike the state-driven tones of the others.
public struct CpSnapshot: Sendable, Equatable, Codable {
    public var site: String          // the location title, e.g. "SEA41"
    public var account: String       // "typhoon.2010" / "Signed out" / "Account unknown"
    public var checkedAt: String     // "9:41 AM" — drives the refresh/"Checked" stamp (empty = hidden)
    public var bigAnswer: String     // the hero: "Sign in" / "12" / "#3" / "Charging" / "Your turn"
    public var unit: String          // the hero's unit line: "plugs free" / "kWh added" / ""
    public var sub: String           // secondary: "Session expired" / "7.4 kW" / "WAITING" / "Respond now"
    public var freeDetail: [String]  // under the big number when idle: ["of 86 plugs", "7 in use", "1 offline"]
    public var plugsFree: String?    // "12 of 86 free" (shown when idle)
    public var autoOn: Bool          // the Auto-waitlist pill
    public var actionLabel: String   // "Sign in" / "Join" / "Open"
    public var showOpen: Bool        // idle: a secondary "Open" key beside the primary action (Android parity)
    public var keys: [CpKey]         // state-specific manual commands (Accept / Snooze / Leave / Rejoin)
    public var deadline: Date?       // when set, a live countdown to the offer/hold/snooze deadline
    public var goTo: String?         // "SEA41-29 P3" — which charger/level to go to (offer / held)
    public var floors: [CpFloor]     // per-level availability (idle, when a location is set)
    public var railNotes: [String]   // extra rail lines under the hero: "1 snooze left" / "Move by 10:14 AM"
    public var stats: [CpStat]       // charging right-panel rows: Est. distance / Time elapsed / Charger
    public var tone: BeaconTone      // always .orange
    public var stale: Bool           // last successful reading retained after a failed check
    public var working: Bool
    public var autoControl: CpAutoControl
    public var origin: CpRenderedOrigin? = nil
    public var statusDescription: String? = nil

    public init(site: String, account: String, bigAnswer: String, unit: String, sub: String,
                plugsFree: String?, autoOn: Bool, actionLabel: String, keys: [CpKey] = [],
                deadline: Date? = nil, goTo: String? = nil, floors: [CpFloor] = [],
                checkedAt: String = "", freeDetail: [String] = [], showOpen: Bool = false,
                railNotes: [String] = [], stats: [CpStat] = [],
                tone: BeaconTone = .orange, stale: Bool = false, working: Bool = false,
                autoControl: CpAutoControl = .disabled) {
        self.site = site; self.account = account; self.checkedAt = checkedAt; self.bigAnswer = bigAnswer
        self.unit = unit; self.sub = sub; self.freeDetail = freeDetail; self.plugsFree = plugsFree
        self.autoOn = autoOn; self.actionLabel = actionLabel; self.showOpen = showOpen
        self.keys = keys; self.deadline = deadline; self.goTo = goTo; self.floors = floors
        self.railNotes = railNotes; self.stats = stats; self.tone = tone
        self.stale = stale
        self.working = working; self.autoControl = autoControl
    }

    /// Sample previews an offered state (keys + a live countdown visible).
    public static let sample = CpSnapshot(
        site: "SEA41", account: "typhoon.2010", bigAnswer: "Your turn", unit: "",
        sub: "Respond now", plugsFree: nil, autoOn: true, actionLabel: "Open",
        keys: [CpKey(command: "accept", label: "Accept"), CpKey(command: "snooze", label: "Snooze")],
        deadline: Date().addingTimeInterval(165), goTo: "SEA41-29 P3")
}
