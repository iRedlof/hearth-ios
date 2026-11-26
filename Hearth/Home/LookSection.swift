import SwiftUI
import HearthKit

/// The "Look" section of the iOS Home dashboard.
/// Single row for Card style customization.
struct LookSection: View {
    private let onTap: (HomeRoute) -> Void

    @Environment(\.colorScheme) private var scheme

    init(onTap: @escaping (HomeRoute) -> Void) {
        self.onTap = onTap
    }

    var body: some View {
        HearthGroup("Look") {
            // TODO Phase 5: dedicated card style route
            Button {
                onTap(.settings)
            } label: {
                HearthRow(
                    icon: "paintpalette.fill",
                    hue: .orange,
                    title: "Card style",
                    subtitle: "Customize widget appearance"
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HearthColor.mute(scheme))
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
