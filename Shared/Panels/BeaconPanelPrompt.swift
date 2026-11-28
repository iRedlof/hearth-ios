import SwiftUI
import AppIntents
import HearthKit

/// What a body shows in place of its items: one message in a well ("Connect Home Assistant",
/// "Checking…"), and under it the one button the person can use (Connect / Sign in / Open
/// Settings), which opens Hearth through `HaSetupIntent`. The Alarm card's setup layout.
struct BeaconPanelPrompt: View {
    let prompt: PanelPrompt
    let look: BeaconLook
    @Environment(\.cardTextScale) private var textScale

    private var ink: Color { Color(argb: look.ink) }

    var body: some View {
        VStack(spacing: 0) {
            BeaconMiddle(maximumHeight: PanelMetrics.promptWellMaximumHeight) {
                Text(prompt.message).font(HearthFont.callout.font(scale: textScale).weight(.semibold))
                    .foregroundStyle(ink).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(PanelMetrics.promptMessageShrink)
                    .padding(.horizontal, PanelMetrics.tileHorizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(argb: look.chipFaint),
                                in: RoundedRectangle(cornerRadius: PanelMetrics.promptWellRadius))
            }
            if let action = prompt.action {
                Button(intent: HaSetupIntent(reconnect: action.reconnect)) { button(action.label) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func button(_ label: String) -> some View {
        Text(label).font(HearthFont.callout.font(scale: textScale).weight(.semibold))
            .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(PanelMetrics.nameShrink)
            .frame(maxWidth: .infinity).frame(height: PanelMetrics.promptButtonHeight)
            .background(Color(argb: look.chip), in: RoundedRectangle(cornerRadius: PanelMetrics.promptButtonRadius))
    }
}
