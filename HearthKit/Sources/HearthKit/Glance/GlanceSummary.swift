import Foundation

// MARK: - Glance At-a-Glance Summary
//
// Ported from Android HomeGlanceState.kt. Answers "is everything OK?" by ranking
// all widget feeds and picking the most severe state. Pure, testable logic.

/// How much an item needs attention. The most severe always leads.
public enum GlanceSeverity: Int, Sendable, Comparable {
    case calm = 0
    case warn = 1
    case act = 2
    case alert = 3
    case alarm = 4

    public static func < (lhs: GlanceSeverity, rhs: GlanceSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Something that needs attention ("Garage open 41 min").
public struct GlanceItem: Sendable, Equatable {
    public let text: String
    public let severity: GlanceSeverity

    public init(text: String, severity: GlanceSeverity) {
        self.text = text
        self.severity = severity
    }
}

/// One placed widget's last reading: when it last checked, whether it failed,
/// what needs attention, and whether it's calm.
public struct GlanceFeed: Sendable, Equatable {
    public let kind: HomeWidgetKind
    public let checkedAt: Date?
    public let error: Bool
    public let items: [GlanceItem]
    public let calm: Bool

    public init(kind: HomeWidgetKind, checkedAt: Date?, error: Bool, items: [GlanceItem], calm: Bool) {
        self.kind = kind
        self.checkedAt = checkedAt
        self.error = error
        self.items = items
        self.calm = calm
    }
}

/// The overall state: OK, needs attention, alarm, can't check, or not set up.
public enum GlanceVerdict: Sendable, Equatable {
    case ok
    case needYou
    case alarm
    case cantCheck
    case empty
}

/// The complete at-a-glance summary: verdict, state word, tone, items needing attention,
/// and the qualifier text.
public struct GlanceSummary: Sendable, Equatable {
    public let verdict: GlanceVerdict
    /// The state word: "OK", "2 need you", "Alarm!", "Can't check", "Set up".
    public let word: String
    public let tone: StatusTone
    /// Everything that needs attention, most severe first.
    public let lines: [String]
    /// The qualifier: "Checked 9:41", "Last known · 9:12", etc.
    public let support: String
    /// OK's coverage: each feed's calm indicator ("Alarm · Doors · Lights").
    public let calmLine: String?

    public init(verdict: GlanceVerdict, word: String, tone: StatusTone, lines: [String], support: String, calmLine: String?) {
        self.verdict = verdict
        self.word = word
        self.tone = tone
        self.lines = lines
        self.support = support
        self.calmLine = calmLine
    }
}

// MARK: - Core Logic

/// The 20-minute freshness threshold (in milliseconds, matching Android).
/// Readings older than this can't vouch for "OK".
public let glanceFreshMs = 20 * 60 * 1000

/// Rank every feed's items and determine the overall state.
public func glanceSummary(_ feeds: [GlanceFeed], now: Date, freshMs: Int = glanceFreshMs) -> GlanceSummary {
    // Empty state: no widgets configured
    if feeds.isEmpty {
        return GlanceSummary(
            verdict: .empty,
            word: "Set up",
            tone: .neutral,
            lines: [],
            support: "Add Alarm, Doors or Lights",
            calmLine: nil
        )
    }

    // Build ranked lines from all items (exclude Calm severity)
    let lines = rankedLines(feeds, now: now, freshMs: freshMs)

    // Determine which feeds are stale (can't vouch for OK)
    let stale = feeds.filter { !$0.isLive(now: now, freshMs: freshMs) }

    // Determine verdict from top item and stale status
    let topSeverity = lines.first.flatMap { text in
        feeds.flatMap(\.items).first { $0.text == text }?.severity
    }

    let verdict: GlanceVerdict
    switch topSeverity {
    case .alarm:
        verdict = .alarm
    case .some:
        verdict = .needYou
    case .none where stale.isEmpty:
        verdict = .ok
    default:
        verdict = .cantCheck
    }

    // Build word based on verdict
    let word: String
    switch verdict {
    case .alarm:
        word = "Alarm!"
    case .needYou:
        word = lines.count == 1 ? "1 needs you" : "\(lines.count) need you"
    case .ok:
        word = "OK"
    case .cantCheck, .empty:
        word = "Can't check"
    }

    // Determine tone
    let tone: StatusTone
    switch verdict {
    case .ok:
        tone = .ok
    case .cantCheck, .empty:
        tone = .neutral
    case .needYou, .alarm:
        // iOS uses .warn for all warning/alert states (no separate red tone)
        tone = .warn
    }

    // Build support qualifier
    let support = buildSupport(feeds: feeds, stale: stale, now: now)

    // Build calmLine if OK (join displayNames of calm feeds)
    let calmLine: String?
    if verdict == .ok {
        let calmFeeds = feeds.filter { $0.calm }
        calmLine = calmFeeds.isEmpty ? nil : calmFeeds.map { $0.kind.displayName }.joined(separator: " · ")
    } else {
        calmLine = nil
    }

    return GlanceSummary(
        verdict: verdict,
        word: word,
        tone: tone,
        lines: lines,
        support: support,
        calmLine: calmLine
    )
}

// MARK: - Private Helpers

/// Returns true if this feed is fresh: checked recently and no error.
private extension GlanceFeed {
    func isLive(now: Date, freshMs: Int) -> Bool {
        guard !error, let checkedAt = checkedAt else {
            return false
        }
        let ageMs = Int((now.timeIntervalSince(checkedAt)) * 1000)
        return ageMs >= 0 && ageMs <= freshMs
    }
}

/// Build ranked lines from all items across feeds.
/// Excludes Calm severity items. Sorts by severity descending.
private func rankedLines(_ feeds: [GlanceFeed], now: Date, freshMs: Int) -> [String] {
    struct Ranked {
        let text: String
        let severity: GlanceSeverity
        let feedIndex: Int
        let itemIndex: Int
    }

    let all = feeds.enumerated().flatMap { feedIdx, feed in
        feed.items.enumerated().compactMap { itemIdx, item -> Ranked? in
            guard item.severity != .calm else { return nil }
            return Ranked(
                text: item.text,
                severity: item.severity,
                feedIndex: feedIdx,
                itemIndex: itemIdx
            )
        }
    }

    // Sort by severity descending, then by feed order, then by item order
    let sorted = all.sorted { lhs, rhs in
        if lhs.severity != rhs.severity {
            return lhs.severity > rhs.severity
        }
        if lhs.feedIndex != rhs.feedIndex {
            return lhs.feedIndex < rhs.feedIndex
        }
        return lhs.itemIndex < rhs.itemIndex
    }

    return sorted.map { $0.text }
}

/// Build the support qualifier text.
private func buildSupport(feeds: [GlanceFeed], stale: [GlanceFeed], now: Date) -> String {
    let oldest = feeds.compactMap(\.checkedAt).min()

    // All feeds are stale
    if stale.count == feeds.count {
        if let oldest = oldest {
            return "Checked \(formatTime(oldest))"
        } else {
            return "Not checked yet"
        }
    }

    // Some feeds are stale (can't check)
    if !stale.isEmpty {
        if let oldest = oldest {
            return "Checked \(formatTime(oldest))"
        } else {
            return "Not checked yet"
        }
    }

    // All fresh: show the oldest check time
    if let oldest = oldest {
        return "Checked \(formatTime(oldest))"
    }

    return "Not checked yet"
}

/// Format a time as "9:41" (local time).
private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
}
