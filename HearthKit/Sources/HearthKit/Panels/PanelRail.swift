import Foundation

/// The two-panel widgets (Lights, Quick actions, Favourites, Activity, Batteries): a tinted left
/// rail with the big answer, a dark right body with the details. Everything the rail says is
/// decided here; the views only draw it.

/// The three rail tones, named for what they mean. They are the existing `DoorsTone` values:
/// the two-panel widgets invent no colour.
public enum PanelTone {
    /// Something is on, or wants attention (amber).
    public static let active: DoorsTone = .warn
    /// Everything is fine (green).
    public static let settled: DoorsTone = .calm
    /// Nothing to judge: not set up, unreachable, or purely informational (neutral).
    public static let neutral: DoorsTone = .unknown
}

/// Wording shared by every two-panel widget.
public enum PanelCopy {
    public static let setupWord = "Set up"
    public static let setupDetail = "Tap to connect"
    public static let connectHome = "Connect Home Assistant"
    public static let checking = "Checking…"
    public static let unavailable = "Unavailable"
    public static let cantRead = "Can't read"
    public static let homeUnreachable = "Home is unreachable"
    public static let couldNotRead = "Couldn't read your home"

    /// "3 lights", "1 action".
    public static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// What a rail says: its glyph (an SF Symbol name), the answer, one detail under it, and its tone.
public struct PanelRail: Sendable, Equatable {
    public let icon: String
    public let word: String
    public let detail: String
    public let tone: DoorsTone

    public init(icon: String, word: String, detail: String, tone: DoorsTone) {
        self.icon = icon; self.word = word; self.detail = detail; self.tone = tone
    }

    /// The longest answer that still reads as one line ("4 actions", "Front Door").
    static let longestOneLineWord = 10

    /// A long answer ("3 not reporting") may wrap to two lines; a short one shrinks to stay on one.
    public var wordLines: Int { word.count > Self.longestOneLineWord ? 2 : 1 }
}

/// Not set up: the same words on every rail, apart from its glyph.
public func panelSetupRail(icon: String) -> PanelRail {
    PanelRail(icon: icon, word: PanelCopy.setupWord, detail: PanelCopy.setupDetail, tone: PanelTone.neutral)
}

/// The first read is still on its way.
public func panelCheckingRail(icon: String) -> PanelRail {
    PanelRail(icon: icon, word: PanelCopy.checking, detail: "", tone: PanelTone.neutral)
}

/// Home Assistant can't be reached: "3 not reporting" over "3 lights". With nothing last known
/// there is no count to give, so the rail says the read failed.
public func panelNotReportingRail(icon: String, count: Int, noun: String) -> PanelRail {
    guard count > 0 else {
        return PanelRail(icon: icon, word: PanelCopy.cantRead, detail: PanelCopy.homeUnreachable,
                         tone: PanelTone.neutral)
    }
    return PanelRail(icon: icon, word: "\(count) not reporting", detail: PanelCopy.counted(count, noun),
                     tone: PanelTone.neutral)
}

/// The tone of an on/off rail (Lights, Favourites): warm while anything is on, calm when all are
/// known to be off, neutral when there is nothing to judge or some did not report.
public func panelOnOffTone(itemCount: Int, onCount: Int, unavailableCount: Int) -> DoorsTone {
    guard itemCount > 0 else { return PanelTone.neutral }
    if onCount > 0 { return PanelTone.active }
    return unavailableCount > 0 ? PanelTone.neutral : PanelTone.settled
}

/// The time to print after "Checked", or nil when there is none: the header then shows the reload
/// button alone, never "Checked —".
public func panelCheckedTime(_ checkedAt: String) -> String? {
    let time = checkedAt.trimmingCharacters(in: .whitespacesAndNewlines)
    return time.isEmpty || time == "—" ? nil : time
}
