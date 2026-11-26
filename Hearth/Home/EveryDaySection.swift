import SwiftUI
import HearthKit

/// The "Every day" section of the iOS Home dashboard.
/// Displays Routines, Leave-by, Travel days, and Safety alerts rows.
struct EveryDaySection: View {
    private let onTap: (HomeRoute) -> Void

    init(onTap: @escaping (HomeRoute) -> Void) {
        self.onTap = onTap
    }

    var body: some View {
        HearthGroup("Every day") {
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
                onTap(.leaveBy)
            } label: {
                HearthRow(
                    icon: "clock.fill",
                    hue: .blue,
                    title: "Leave-by times",
                    subtitle: leaveBySubtitle
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)

            Button {
                onTap(.travelDays)
            } label: {
                HearthRow(
                    icon: "airplane",
                    hue: .amber,
                    title: "Travel days",
                    subtitle: travelDaysSubtitle
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)

            Button {
                onTap(.safetyAlerts)
            } label: {
                HearthRow(
                    icon: "bell.badge.fill",
                    hue: .red,
                    title: "Safety alerts",
                    subtitle: safetyAlertsSubtitle
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var leaveBySubtitle: String {
        guard HouseFeaturesStore.leaveByEnabled else { return "Off" }
        return "\(HouseFeaturesStore.leaveByMinutes) min before events with a place"
    }

    private var travelDaysSubtitle: String {
        guard HouseFeaturesStore.travelEnabled else { return "Off" }
        return "Vacation mode the night before"
    }

    private var safetyAlertsSubtitle: String {
        guard HouseFeaturesStore.safetyEnabled else { return "Off" }
        return "When a close, lock or arm fails"
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
