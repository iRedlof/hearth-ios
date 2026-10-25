import SwiftUI
import AppIntents

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
