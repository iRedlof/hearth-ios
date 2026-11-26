import SwiftUI
import HearthKit

/// The "Every day" section of the iOS Home dashboard.
/// Displays Routines, Leave-by, Travel days, and Safety alerts rows.
/// Routes to Settings for now (Phase 5 will add dedicated destinations).
struct EveryDaySection: View {
    private let onTap: (HomeRoute) -> Void

    init(onTap: @escaping (HomeRoute) -> Void) {
        self.onTap = onTap
    }

    var body: some View {
        HearthGroup("Every day") {
            // TODO Phase 5: dedicated routes for each feature
            Button {
                onTap(.settings)
            } label: {
                HearthRow(
                    icon: "arrow.triangle.2.circlepath",
                    hue: .purple,
                    title: "Routines",
                    subtitle: "Automate your day"
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)

            Button {
                onTap(.settings)
            } label: {
                HearthRow(
                    icon: "clock.fill",
                    hue: .blue,
                    title: "Leave-by times",
                    subtitle: "Smart departure alerts"
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)

            Button {
                onTap(.settings)
            } label: {
                HearthRow(
                    icon: "airplane",
                    hue: .amber,
                    title: "Travel days",
                    subtitle: "Away mode & vacation"
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)

            Button {
                onTap(.settings)
            } label: {
                HearthRow(
                    icon: "bell.badge.fill",
                    hue: .red,
                    title: "Safety alerts",
                    subtitle: "Critical notifications"
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Previews

#Preview("Every day — Light") {
    EveryDaySection(onTap: { _ in })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.light))
        .preferredColorScheme(.light)
}

#Preview("Every day — Dark") {
    EveryDaySection(onTap: { _ in })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.dark))
        .preferredColorScheme(.dark)
}
