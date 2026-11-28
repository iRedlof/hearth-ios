import SwiftUI
import HearthKit

/// The Activity widget (medium, two-panel, read-only). Rail: the latest event of the last 24
/// hours, what and when. Body: the events before it, three rows at most, then "+N more". When
/// Home Assistant can't be reached the last-known events stay under a notice.
public struct ActivityPanelView: View {
    public let snap: ActivitySnapshot
    private let referenceNow: Date?
    @Environment(\.cardStyle) private var cardStyle
    /// Fixtures pass `now`; the Home Screen widget uses the time it is drawn.
    public init(_ snap: ActivitySnapshot, now: Date? = nil) { self.snap = snap; self.referenceNow = now }

    private var look: BeaconLook { beaconLook(cardStyle) }
    private var ink: Color { Color(argb: look.ink) }

    public var body: some View {
        let panel = activityPanel(snap, now: referenceNow ?? Date())
        BeaconTwoPanel {
            BeaconStatusRail(panel.rail)
        } surface: {
            BeaconPanelBody(title: "Activity", kind: "com.rohit.hearth.activity", checked: panel.checked,
                            notice: panel.notice, prompt: panel.prompt) {
                if let note = panel.note {
                    Text(note).font(HearthFont.footnote.font(scale: look.textScale))
                        .foregroundStyle(ink.opacity(PanelMetrics.secondaryOpacity))
                } else {
                    ViewThatFits(in: .vertical) {
                        ForEach(PanelRowFit.choices, id: \.self) { rows(panel.rows, limit: $0) }
                    }
                }
            }
        }
    }

    private func rows(_ all: [ActivityPanelRow], limit: Int) -> some View {
        let page = panelPage(all, limit: limit)
        return VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            ForEach(page.shown) { ActivityPanelRowView(row: $0, ink: ink) }
            if let more = page.moreLabel {
                BeaconPanelMore(label: more, opensSettings: false, ink: ink).padding(.top, PanelMetrics.moreGap)
            }
        }
    }
}
