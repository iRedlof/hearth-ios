import SwiftUI
import HearthKit

/// Reusable chevron icon for Home dashboard rows.
struct HomeChevron: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(HearthFont.callout.font.weight(.semibold))
            .foregroundStyle(HearthColor.mute(scheme))
    }
}
