import Foundation

// MARK: - Glance Layout Engine
//
// Ported from Android HomeGlanceLayout.kt. Plans what fits on a 2x1 or 2x2 widget:
// word size, item lines, support text, safe key, calm line. Pure, testable logic.

/// Widget slot sizes for Glance layout.
public enum GlanceSize: Sendable, Equatable {
    case small2x1
    case small2x2

    /// Approximate dimensions in dp (device-independent pixels).
    public var dimensions: (width: Float, height: Float) {
        switch self {
        case .small2x1:
            return (170, 72)  // Typical 2x1 dimensions
        case .small2x2:
            return (170, 184) // Typical 2x2 dimensions
        }
    }
}

/// The complete layout plan for a Glance widget.
public struct GlanceLayoutPlan: Sendable, Equatable {
    /// Widget is compact (2x1) vs tall (2x2).
    public let compact: Bool
    /// The state word ("OK", "2 need you", "Alarm!", etc).
    public let word: String
    /// How many item lines are shown (0-2).
    public let showsLines: Int
    /// Whether the calm line ("Alarm · Doors · Lights") is shown.
    public let showsCalmLine: Bool
    /// Whether the support qualifier ("Checked 9:41") is shown.
    public let showsSupport: Bool
    /// Whether the safe key (Check/Disarm) is shown.
    public let showsKey: Bool
    /// The word is never shortened (always shows in full).
    public var wordNeverShortened: Bool { true }

    public init(compact: Bool, word: String, showsLines: Int, showsCalmLine: Bool, showsSupport: Bool, showsKey: Bool) {
        self.compact = compact
        self.word = word
        self.showsLines = showsLines
        self.showsCalmLine = showsCalmLine
        self.showsSupport = showsSupport
        self.showsKey = showsKey
    }
}

// MARK: - Layout Logic

/// Under this height it's the 2x1 layout.
private let glanceCompactBelowDp: Float = 100

/// Plans the Glance layout for a given summary and size.
/// The word is never shortened — it may step down in size, but always shows in full.
/// Uses a simplified capacity model for text measurement (deterministic for tests).
public func glanceLayout(summary: GlanceSummary, size: GlanceSize) -> GlanceLayoutPlan {
    let (widthDp, heightDp) = size.dimensions
    let compact = heightDp < glanceCompactBelowDp

    // Determine what fits based on content and size
    let hasLines = !summary.lines.isEmpty
    let hasSupport = !summary.support.isEmpty
    let hasCalmLine = summary.calmLine != nil

    // Priority order (from Android):
    // 1. Honesty qualifier (required when needed)
    // 2. Top item
    // 3. Key
    // 4. Plain qualifier
    // 5. Second item
    // 6. Calm line

    let honestyRequired = glanceHonestyRequired(summary)

    // Determine layout based on compact vs tall
    var showsLines = 0
    var showsCalmLine = false
    var showsSupport = false
    var showsKey = false

    if compact {
        // 2x1: word + 1-2 lines OR key beside, support inline or omitted
        let keyCanFit = summary.key != nil && canKeyFitBeside(word: summary.word, widthDp: widthDp)

        // Show top item if present
        if hasLines {
            showsLines = min(summary.lines.count, 2)
        }

        // Show support if required (honesty) and has room
        if honestyRequired && hasSupport {
            // Support can be inline beside word or omitted if no room
            showsSupport = canSupportFitInline(word: summary.word, support: summary.support, widthDp: widthDp)
        }

        // Key beside word if it fits (and no lines or lines leave room)
        if keyCanFit && showsLines <= 1 {
            showsKey = true
        }
    } else {
        // 2x2: more room, can show more content

        // Show up to 2 item lines
        if hasLines {
            showsLines = min(summary.lines.count, 2)
        }

        // Show support if present
        if hasSupport {
            showsSupport = true
        }

        // Show calm line if OK and present
        if hasCalmLine {
            showsCalmLine = true
        }

        // Show key under content if present
        if summary.key != nil {
            showsKey = true
        }
    }

    return GlanceLayoutPlan(
        compact: compact,
        word: summary.word,
        showsLines: showsLines,
        showsCalmLine: showsCalmLine,
        showsSupport: showsSupport,
        showsKey: showsKey
    )
}

// MARK: - Private Helpers

/// Whether the honesty qualifier is required: last-known item, OK's time, or Can't check's why.
private func glanceHonestyRequired(_ summary: GlanceSummary) -> Bool {
    // Check if top item is "last known" (not implemented in GlanceSummary yet, so assume false)
    // For now, honesty is required for OK or CantCheck
    return summary.verdict == .ok || summary.verdict == .cantCheck
}

/// Approximate text width in dp using a simplified character-based model.
/// This is deterministic for tests (doesn't depend on actual font metrics).
private func approxTextWidth(_ text: String) -> Float {
    // Simplified from Android: each character has an approximate width
    // Narrow chars (~0.3em), wide (~0.88em), capitals (~0.66em), letters (~0.56em)
    // Using rough average of ~6dp per character for 12sp text
    let charCount = Float(text.count)
    return charCount * 6.0
}

/// Can the key fit beside the word on a 2x1?
private func canKeyFitBeside(word: String, widthDp: Float) -> Bool {
    let wordWidth = approxTextWidth(word)
    let keyWidth: Float = 60 // Approximate key button width
    let gap: Float = 8
    let padding: Float = 24 // Left + right padding
    return wordWidth + gap + keyWidth + padding <= widthDp
}

/// Can the support text fit inline beside the word?
private func canSupportFitInline(word: String, support: String, widthDp: Float) -> Bool {
    let wordWidth = approxTextWidth(word)
    let supportWidth = approxTextWidth(support)
    let gap: Float = 6
    let padding: Float = 24
    return wordWidth + gap + supportWidth + padding <= widthDp
}
