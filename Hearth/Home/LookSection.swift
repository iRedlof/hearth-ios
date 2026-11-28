import SwiftUI
import HearthKit

/// The "Look" section of the iOS Home dashboard.
/// Single row for Card style, with the All-cards style in a few words underneath
/// (Android `HomeScreen.kt:91-93`).
struct LookSection: View {
    private let summary: String
    private let onTap: (HomeRoute) -> Void

    init(summary: String, onTap: @escaping (HomeRoute) -> Void) {
        self.summary = summary
        self.onTap = onTap
    }

    var body: some View {
        HearthGroup("Look") {
            Button {
                onTap(.cardStyle(nil))
            } label: {
                HearthRow(
                    icon: "paintpalette.fill",
                    hue: .orange,
                    title: "Card style",
                    subtitle: summary
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Previews

#Preview("Look — Light") {
    LookSection(summary: CardStyle.default.summary, onTap: { _ in })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.light))
        .preferredColorScheme(.light)
}

#Preview("Look — Dark") {
    LookSection(summary: CardStyle.default.summary, onTap: { _ in })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.dark))
        .preferredColorScheme(.dark)
}
