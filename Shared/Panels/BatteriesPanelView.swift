import SwiftUI
import HearthKit

/// The Batteries widget (medium, two-panel). Rail: "All good" (green) or "2 low" (amber) with what
/// is low. Body: the lowest batteries, three rows at most, then "+N more". When Home Assistant
/// can't be reached the last-known levels stay, on a neutral rail.
public struct BatteriesPanelView: View {
    public let snap: BatterySnapshot
    @Environment(\.cardStyle) private var cardStyle
    public init(_ snap: BatterySnapshot) { self.snap = snap }

    private var look: BeaconLook { beaconLook(cardStyle) }
    private var ink: Color { Color(argb: look.ink) }

    public var body: some View {
        let panel = batteryPanel(snap)
        BeaconTwoPanel {
            BeaconStatusRail(panel.rail)
        } surface: {
            BeaconPanelBody(title: "Batteries", kind: "com.rohit.hearth.battery", checked: panel.checked,
                            notice: panel.notice, prompt: panel.prompt) {
                ViewThatFits(in: .vertical) {
                    ForEach(PanelRowFit.choices, id: \.self) { rows(panel.rows, limit: $0) }
                }
            }
        }
    }

    private func rows(_ all: [BatteryPanelRow], limit: Int) -> some View {
        let page = panelPage(all, limit: limit)
        return VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            ForEach(page.shown) { BatteryPanelRowView(row: $0, look: look) }
            if let more = page.moreLabel {
                BeaconPanelMore(label: more, opensSettings: false, ink: ink).padding(.top, PanelMetrics.moreGap)
            }
        }
    }
}
