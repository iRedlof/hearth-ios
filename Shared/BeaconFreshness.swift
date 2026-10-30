import SwiftUI
import AppIntents

/// The card remains compact while its host's middle region expands between header and footer.
struct BeaconMiddle<Content: View>: View {
    var maximumHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            content()
                .frame(maxWidth: .infinity)
                .frame(height: min(maximumHeight, geometry.size.height))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .padding(.vertical, 8)
    }
}

/// The shared freshness cluster for every widget header: the "Checked <time>" stamp with a **circular
/// reload button to its RIGHT** (ported from Android's raised circular refresh). Used everywhere so the
/// wording ("Checked") and the reload button are identical across all widgets, iOS and — once ported —
/// Android. `invalidatableContent()` dims the stamp "updating" from tap until fresh data lands.
struct BeaconFreshness: View {
    let checkedAt: String
    let kind: String      // widget kind id, for WidgetRefreshIntent
    var ink: Color

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: -1) {
                Text("Checked").font(.system(size: 10))
                Text(checkedAt).font(.system(size: 10))
            }
            .foregroundStyle(ink.opacity(0.78))
            .invalidatableContent()
            Button(intent: WidgetRefreshIntent(kind)) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(ink.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
