import SwiftUI
import HearthKit

/// Large "Hearth" title for the Home screen, with optional toast.
struct HomeHeader: View {
    @Environment(\.colorScheme) var colorScheme
    var toast: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hearth")
                .font(HearthFont.largeTitle.font)
                .foregroundStyle(HearthColor.ink(colorScheme))

            if let toast {
                Text(toast)
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.mute(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(HearthColor.tint(colorScheme))
                    .cornerRadius(8)
            }
        }
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

#Preview("With Toast - Light") {
    HomeHeader(toast: "Signed in")
        .preferredColorScheme(.light)
}

#Preview("With Toast - Dark") {
    HomeHeader(toast: "Signed in")
        .preferredColorScheme(.dark)
}
