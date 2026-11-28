import SwiftUI
import HearthKit

/// The right half of a two-panel widget, on the body the Card style paints: the header, then
/// either the prompt (not set up, checking, nothing found) or the notice and the items.
///
/// `items` is given all the height left and must fit it: each widget offers `ViewThatFits` its
/// layouts from fullest to barest.
struct BeaconPanelBody<Items: View>: View {
    let title: String
    let kind: String
    let checked: String?
    let notice: String?
    let prompt: PanelPrompt?
    @ViewBuilder let items: () -> Items
    @Environment(\.cardStyle) private var cardStyle

    private var look: BeaconLook { beaconLook(cardStyle) }
    private var ink: Color { Color(argb: look.ink) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BeaconPanelHeader(title: title, kind: kind, checked: checked, ink: ink)
            if let prompt {
                BeaconPanelPrompt(prompt: prompt, look: look)
            } else {
                if let notice {
                    BeaconPanelNotice(message: notice, ink: ink).padding(.top, PanelMetrics.noticeGap)
                }
                items()
                    .padding(.top, PanelMetrics.sectionGap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, PanelMetrics.bodyHorizontalPadding)
        .padding(.top, PanelMetrics.bodyTopPadding)
        .padding(.bottom, PanelMetrics.bodyBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
