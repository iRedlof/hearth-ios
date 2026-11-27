import SwiftUI
import HearthKit

/// Large "Hearth" title for the Home screen.
struct HomeHeader: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text("Hearth")
            .font(HearthFont.largeTitle.font)
            .foregroundStyle(HearthColor.ink(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
    }
}

#Preview("Light") {
    HomeHeader()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeHeader()
        .preferredColorScheme(.dark)
}
