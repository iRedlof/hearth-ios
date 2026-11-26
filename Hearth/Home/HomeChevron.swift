import SwiftUI
import HearthKit

/// Reusable chevron icon for Home dashboard rows.
struct HomeChevron: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(HearthColor.mute(scheme))
    }
}
