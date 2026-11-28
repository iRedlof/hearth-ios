import SwiftUI
import HearthKit

/// A Beacon rail in the Alarm card's grammar: the state glyph at the top, the answer in heavy
/// type at the bottom, one detail under it. The rail keeps the widget's own state colour and ink
/// whatever the Card style.
///
/// It always fits its height: the glyph and the answer shrink first, then the detail gives up
/// lines (`PanelRailFit`). A detail line stays on one line when it can, slightly smaller if that
/// is all it takes, and wraps otherwise, so it is never cut mid-word.
struct BeaconStatusRail: View {
    let icon: String
    let word: String
    /// 2: the answer may wrap ("3 not reporting", "Armed home"); 1: it shrinks to stay on its line.
    let wordLines: Int
    /// A long answer is set in the smaller of the two answer sizes.
    let longWord: Bool
    /// Lines separated by "\n" are drawn as separate lines.
    let detail: String
    let fillARGB: UInt32
    let inkARGB: UInt32
    /// What VoiceOver reads for the detail when it differs from the text shown.
    var detailAccessibilityLabel: String? = nil
    @Environment(\.cardTextScale) private var textScale

    private var ink: Color { Color(argb: inkARGB) }
    private var detailLines: [String] {
        detail.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(PanelRailFit.choices, id: \.self) { column($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BeaconRailBackground(fillARGB: fillARGB, fade: PanelMetrics.railFade))
    }

    private func column(_ fit: PanelRailFit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon).font(.system(size: fit.iconSize, weight: .semibold)).foregroundStyle(ink)
            Spacer(minLength: PanelMetrics.railGlyphGap)
            answer(fit)
            details(lines: fit.detailLines)
        }
        .padding(.horizontal, PanelMetrics.railHorizontalPadding)
        .padding(.vertical, PanelMetrics.railVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func answer(_ fit: PanelRailFit) -> some View {
        Text(word)
            .font(.system(size: (longWord ? fit.longWordSize : fit.wordSize) * textScale, weight: .heavy))
            .tracking(PanelMetrics.railWordTracking)
            .foregroundStyle(ink)
            .lineLimit(wordLines).minimumScaleFactor(PanelMetrics.railWordShrink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// As many of the detail's lines as `lines` allows. Each may wrap into the lines the others
    /// leave when they keep to one; if more than one wraps the column is taller, and a rail that
    /// then does not fit falls to the next `PanelRailFit`.
    @ViewBuilder private func details(lines: Int) -> some View {
        let shown = Array(detailLines.prefix(lines))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                    detailLine(line, wrapLines: lines - shown.count + 1)
                }
            }
            .padding(.top, PanelMetrics.railDetailGap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(detailAccessibilityLabel ?? detail)
        }
    }

    private func detailLine(_ line: String, wrapLines: Int) -> some View {
        // The first two test their natural width: a truncating one-line Text would always "fit".
        ViewThatFits(in: .horizontal) {
            detailText(line, scale: 1).lineLimit(1).fixedSize()
            detailText(line, scale: PanelMetrics.railDetailShrink).lineLimit(1).fixedSize()
            detailText(line, scale: wrapLines > 1 ? 1 : PanelMetrics.railDetailShrink)
                .lineLimit(wrapLines).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailText(_ line: String, scale: CGFloat) -> some View {
        Text(line).font(HearthFont.footnote.font(scale: textScale * scale))
            .foregroundStyle(ink.opacity(PanelMetrics.railDetailOpacity))
            .multilineTextAlignment(.leading)
    }
}

extension BeaconStatusRail {
    /// A two-panel widget's rail, as HearthKit decided it.
    init(_ rail: PanelRail) {
        self.init(icon: rail.icon, word: rail.word, wordLines: rail.wordLines, longWord: rail.wordLines > 1,
                  detail: rail.detail, fillARGB: rail.tone.fillARGB, inkARGB: rail.tone.inkARGB)
    }
}
