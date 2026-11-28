import SwiftUI
import HearthKit

/// At-a-glance widget view: a single card showing "is everything OK?" with optional items.
public struct GlanceView: View {
    private let summary: GlanceSummary
    private let plan: GlanceLayoutPlan
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardStyle) private var cardStyle

    public init(summary: GlanceSummary, plan: GlanceLayoutPlan) {
        self.summary = summary
        self.plan = plan
    }

    /// Status is the verdict-tinted card; a colour or black shows "needs you" as an accent, and an
    /// alarm keeps its own colours whatever the style (the way Android's non-Beacon cards do).
    private var look: CardLook {
        cardLook(cardStyle, warn: summary.verdict == .needYou, emergency: summary.verdict == .alarm)
    }
    private var textScale: CGFloat { look.textScale }
    private var ink: Color { look.statusColours ? HearthColor.ink(colorScheme) : Color(argb: look.ink) }
    private var wordInk: Color { look.statusColours ? ink : Color(argb: look.headline) }
    private var subInk: Color { look.statusColours ? HearthColor.sub(colorScheme) : Color(argb: look.soft) }
    private var muteInk: Color { look.statusColours ? HearthColor.mute(colorScheme) : Color(argb: look.faint) }
    private var keyInk: Color { look.statusColours ? HearthColor.accent(colorScheme) : Color(argb: look.ink) }
    private var keyFill: Color { look.statusColours ? HearthColor.card(colorScheme) : Color(argb: look.key) }
    /// "Checked …" is small print; a line that tells you what to do is not.
    private var showsSupport: Bool {
        plan.showsSupport && glanceShowsSupport(summary.support, smallPrint: look.smallPrint)
    }

    public var body: some View {
        ZStack {
            // Surface tinted by the verdict tone, or painted by the Card style
            if let surface = look.surface {
                CardSurfaceView(surface).ignoresSafeArea()
            } else {
                summary.tone.bg(colorScheme)
                    .ignoresSafeArea()
            }
            CardStatusStrip(look: look)

            VStack(alignment: .leading, spacing: plan.compact ? 6 : 8) {
                // Top row: verdict word (always shown) + optional inline support/key
                HStack(alignment: .center, spacing: 6) {
                    Text(plan.word)
                        .font(HearthFont.cardHeading.font(scale: textScale))
                        .foregroundColor(wordInk)
                        .lineLimit(1)

                    Spacer()

                    // Key beside word (compact only, if showsKey + compact)
                    if plan.showsKey && plan.compact {
                        keyButton
                    }

                    // Support inline beside word (compact only, if showsSupport + no key OR no room)
                    if showsSupport && plan.compact && !plan.showsKey {
                        Text(summary.support)
                            .font(HearthFont.subtitle.font(scale: textScale))
                            .foregroundColor(subInk)
                            .lineLimit(1)
                    }
                }

                // Item lines (up to plan.showsLines)
                if plan.showsLines > 0 {
                    ForEach(summary.lines.prefix(plan.showsLines), id: \.self) { line in
                        Text(line)
                            .font(HearthFont.subtitle.font(scale: textScale))
                            .foregroundColor(ink)
                            .lineLimit(1)
                    }
                }

                // Support text (tall only, if showsSupport)
                if showsSupport && !plan.compact {
                    Text(summary.support)
                        .font(HearthFont.subtitle.font(scale: textScale))
                        .foregroundColor(subInk)
                        .lineLimit(1)
                }

                // Calm line (tall only, OK state)
                if plan.showsCalmLine, let calmLine = summary.calmLine {
                    Text(calmLine)
                        .font(HearthFont.subtitle.font(scale: textScale))
                        .foregroundColor(muteInk)
                        .lineLimit(1)
                }

                Spacer()

                // Key button at bottom (tall only, if showsKey)
                if plan.showsKey && !plan.compact {
                    HStack {
                        Spacer()
                        keyButton
                    }
                }
            }
            .padding(HearthMetrics.mediumPadding)
        }
    }

    private var keyButton: some View {
        Group {
            if let key = summary.key {
                Text(key.label)
                    .font(HearthFont.button.font(scale: textScale))
                    .foregroundColor(keyInk)
                    .padding(.horizontal, HearthMetrics.mediumPadding)
                    .padding(.vertical, 6)
                    .background(keyFill)
                    .cornerRadius(HearthMetrics.chipRadius)
            }
        }
    }
}

#if DEBUG
#Preview("OK") {
    let summary = GlanceSummary(
        verdict: .ok,
        word: "OK",
        tone: .ok,
        lines: [],
        support: "Checked 9:41",
        calmLine: "Alarm · Doors · Lights",
        key: GlanceKey(label: "Check", action: .refresh)
    )
    let plan = glanceLayout(summary: summary, size: .small2x1)
    return GlanceView(summary: summary, plan: plan)
        .frame(width: 170, height: 72)
        .previewDisplayName("OK (2x1)")
}

#Preview("Need You") {
    let summary = GlanceSummary(
        verdict: .needYou,
        word: "2 need you",
        tone: .warn,
        lines: ["Garage open 41 min", "Office light on 3h"],
        support: "Checked 9:41",
        calmLine: nil,
        key: nil
    )
    let plan = glanceLayout(summary: summary, size: .small2x2)
    return GlanceView(summary: summary, plan: plan)
        .frame(width: 170, height: 184)
        .previewDisplayName("Need You (2x2)")
}

#Preview("Alarm") {
    let summary = GlanceSummary(
        verdict: .alarm,
        word: "Alarm!",
        tone: .warn,
        lines: ["Alarm triggered 2 min"],
        support: "Checked 9:41",
        calmLine: nil,
        key: GlanceKey(label: "Disarm", action: .disarm)
    )
    let plan = glanceLayout(summary: summary, size: .small2x2)
    return GlanceView(summary: summary, plan: plan)
        .frame(width: 170, height: 184)
        .previewDisplayName("Alarm (2x2)")
}

#Preview("Can't Check") {
    let summary = GlanceSummary(
        verdict: .cantCheck,
        word: "Can't check",
        tone: .neutral,
        lines: [],
        support: "Checked 9:12",
        calmLine: nil,
        key: GlanceKey(label: "Try again", action: .refresh)
    )
    let plan = glanceLayout(summary: summary, size: .small2x1)
    return GlanceView(summary: summary, plan: plan)
        .frame(width: 170, height: 72)
        .previewDisplayName("Can't Check (2x1)")
}

#Preview("Empty") {
    let summary = GlanceSummary(
        verdict: .empty,
        word: "Set up",
        tone: .neutral,
        lines: [],
        support: "Add Alarm, Doors or Lights",
        calmLine: nil,
        key: nil
    )
    let plan = glanceLayout(summary: summary, size: .small2x1)
    return GlanceView(summary: summary, plan: plan)
        .frame(width: 170, height: 72)
        .previewDisplayName("Empty (2x1)")
}
#endif
