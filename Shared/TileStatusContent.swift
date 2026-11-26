import SwiftUI
import HearthKit

/// Center the truthful empty/setup state in the room left beneath the common header.
struct TileStatusContent: View {
    let state: TileSnapshotState
    let error: String?
    let choice: String
    let empty: String
    var ink: Color = Color(argb: BeaconSurfaceColors.inkARGB)
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
            Text(label).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.center)
            if let error { Text(error).font(.system(size: 13)).multilineTextAlignment(.center) }
            if state == .setup || state == .choose || beaconNeedsSettings(error) {
                Button(intent: HaSetupIntent(reconnect: beaconNeedsSignIn(error))) {
                    Text(state == .choose ? "Open Settings" : "Connect").font(.system(size: 14, weight: .semibold))
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
    var body: some View {
        Button(intent: HaSetupIntent(reconnect: false)) {
            Text("\(count) more · Settings").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(argb: BeaconSurfaceColors.inkARGB).opacity(0.8))
        }.buttonStyle(.plain)
    }
}
