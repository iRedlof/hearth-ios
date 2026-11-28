import SwiftUI
import AppIntents
import HearthKit

/// "+2 more" under a body's items.
///
/// Under tiles it opens Hearth's settings, where the rest can be reached, exactly as the flat
/// cards' "N more · Settings" did; under read-only rows it is only a count.
struct BeaconPanelMore: View {
    let label: String
    let opensSettings: Bool
    let ink: Color
    @Environment(\.cardTextScale) private var textScale

    var body: some View {
        if opensSettings {
            Button(intent: HaSetupIntent(reconnect: false)) { text }.buttonStyle(.plain)
        } else {
            text
        }
    }

    private var text: some View {
        Text(label).font(HearthFont.caption.font(scale: textScale))
            .foregroundStyle(ink.opacity(PanelMetrics.faintOpacity)).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
