import SwiftUI
import HearthKit

/// The "Look" section of the iOS Home dashboard.
/// Single row for Card style customization.
struct LookSection: View {
    private let onTap: (HomeRoute) -> Void

    init(onTap: @escaping (HomeRoute) -> Void) {
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
                    subtitle: "Customize widget appearance"
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
    LookSection(onTap: { _ in })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.light))
        .preferredColorScheme(.light)
}

#Preview("Look — Dark") {
    LookSection(onTap: { _ in })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.dark))
        .preferredColorScheme(.dark)
}
