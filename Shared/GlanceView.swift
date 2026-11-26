import SwiftUI
import HearthKit

/// At-a-glance widget view: a single card showing "is everything OK?" with optional items.
public struct GlanceView: View {
    private let summary: GlanceSummary
    private let plan: GlanceLayoutPlan
    @Environment(\.colorScheme) private var colorScheme

    public init(summary: GlanceSummary, plan: GlanceLayoutPlan) {
        self.summary = summary
        self.plan = plan
    }

    public var body: some View {
        ZStack {
            // Surface tinted by the verdict tone
            summary.tone.bg(colorScheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: plan.compact ? 6 : 8) {
                // Top row: verdict word (always shown) + optional inline support/key
                HStack(alignment: .center, spacing: 6) {
                    Text(plan.word)
                        .font(HearthFont.cardHeading.font)
                        .foregroundColor(HearthColor.ink(colorScheme))
                        .lineLimit(1)

                    Spacer()

                    // Key beside word (compact only, if showsKey + compact)
                    if plan.showsKey && plan.compact {
                        keyButton
                    }

                    // Support inline beside word (compact only, if showsSupport + no key OR no room)
                    if plan.showsSupport && plan.compact && !plan.showsKey {
                        Text(summary.support)
                            .font(HearthFont.subtitle.font)
                            .foregroundColor(HearthColor.sub(colorScheme))
                            .lineLimit(1)
                    }
                }

                // Item lines (up to plan.showsLines)
                if plan.showsLines > 0 {
                    ForEach(summary.lines.prefix(plan.showsLines), id: \.self) { line in
                        Text(line)
                            .font(HearthFont.subtitle.font)
                            .foregroundColor(HearthColor.ink(colorScheme))
                            .lineLimit(1)
                    }
                }

                // Support text (tall only, if showsSupport)
                if plan.showsSupport && !plan.compact {
                    Text(summary.support)
                        .font(HearthFont.subtitle.font)
                        .foregroundColor(HearthColor.sub(colorScheme))
                        .lineLimit(1)
                }

                // Calm line (tall only, OK state)
                if plan.showsCalmLine, let calmLine = summary.calmLine {
                    Text(calmLine)
                        .font(HearthFont.subtitle.font)
                        .foregroundColor(HearthColor.mute(colorScheme))
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
            .padding(12)
        }
    }

    private var keyButton: some View {
        Group {
            if let key = summary.key {
                Text(key.label)
                    .font(HearthFont.button.font)
                    .foregroundColor(HearthColor.accent(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(HearthColor.card(colorScheme))
                    .cornerRadius(8)
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
