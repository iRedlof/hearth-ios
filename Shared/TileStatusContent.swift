import SwiftUI
import HearthKit

/// Center the truthful empty/setup state in the room left beneath the common header.
struct TileStatusContent: View {
    let state: TileSnapshotState
    let error: String?
    let choice: String
    let empty: String
    /// The host card's ink (its own on Status, the Card style's on a chosen background).
    let ink: Color
    @Environment(\.cardTextScale) private var textScale
    private var label: String {
        switch state {
        case .setup: "Connect Home Assistant"
        case .choose: choice
        case .loading: "Checking…"
        case .failed: "Couldn't read your home"
        case .ready, .empty: empty
        }
    }
    var body: some View {
        VStack(spacing: 8) {
            Text(label).font(HearthFont.cardHeading.font(scale: textScale).weight(.semibold)).multilineTextAlignment(.center)
            if let error { Text(error).font(HearthFont.groupLabel.font(scale: textScale)).multilineTextAlignment(.center) }
            if state == .setup || state == .choose || beaconNeedsSettings(error) {
                Button(intent: HaSetupIntent(reconnect: beaconNeedsSignIn(error))) {
                    Text(state == .choose ? "Open Settings" : "Connect").font(HearthFont.callout.font(scale: textScale).weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(ink.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TileMoreContent: View {
    let count: Int
    let ink: Color
    @Environment(\.cardTextScale) private var textScale
    var body: some View {
        Button(intent: HaSetupIntent(reconnect: false)) {
            Text("\(count) more · Settings").font(HearthFont.footnote.font(scale: textScale).weight(.semibold))
                .foregroundStyle(ink.opacity(0.8))
        }.buttonStyle(.plain)
    }
}
