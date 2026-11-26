import SwiftUI
import HearthKit

/// Version footer with centered version string and update check affordance.
struct HomeFooter: View {
    @Environment(\.colorScheme) var colorScheme

    private var versionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return hearthVersionString(short: shortVersion, build: buildVersion)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(versionText)
                .font(HearthFont.subtitle.font)
                .foregroundColor(HearthColor.mute(colorScheme))

            Button(action: {
                // TODO Phase 6: iOS has no Sparkle; wire an updater affordance
            }) {
                Text("Check for updates")
                    .font(HearthFont.subtitle.font)
                    .foregroundColor(HearthColor.mute(colorScheme))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }
}

#Preview("Light") {
    HomeFooter()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeFooter()
        .preferredColorScheme(.dark)
}
