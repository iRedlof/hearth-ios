import SwiftUI
import HearthKit
import UserNotifications

/// Safety alerts settings page — failure notifications.
/// Enables the feature, shows retry behavior, and handles notification permissions.
@MainActor
struct SafetyAlertsPage: View {
    @State private var enabled: Bool
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    @Environment(\.colorScheme) private var scheme

    init() {
        _enabled = State(initialValue: HouseFeaturesStore.safetyEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Safety alerts")
                    .font(HearthFont.pageTitle.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                Text("If a close, lock or arm fails")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HearthMetrics.groupInset + 12)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 20) {
                    // Enable toggle
                    HearthGroup {
                        HearthRow(
                            icon: "shield",
                            hue: .neutral,
                            title: "Safety alerts",
                            subtitle: enabled ? "On" : "Off"
                        ) {
                            HearthSwitch(isOn: Binding(
                                get: { enabled },
                                set: { newValue in
                                    enabled = newValue
                                    HouseFeaturesStore.safetyEnabled = newValue

                                    // Request notification permission when enabling (if not determined)
                                    if newValue && notificationStatus == .notDetermined {
                                        Task {
                                            let granted = await HouseNotify.requestPermission()
                                            notificationStatus = granted ? .authorized : .denied
                                        }
                                    }
                                }
                            ))
                        }
                    }

                    // Notifications denied banner (only when enabled)
                    if notificationBannerState(enabled: enabled, hasNotificationAccess: notificationStatus == .authorized) == .needsPermission {
                        notificationsDeniedBanner
                    }

                    // Description sections (always show)
                    failureDescriptionSection
                    retryDescriptionSection
                }
                .padding(.bottom, 20)
            }
        }
        .background(HearthColor.page(scheme))
        .task {
            notificationStatus = await HouseNotify.authorizationStatus()
        }
    }

    // MARK: - Notifications Denied Banner

    @ViewBuilder
    private var notificationsDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(HearthFont.iconLarge.font)
                    .foregroundStyle(HearthColor.amber(scheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications are off for Hearth")
                        .font(HearthFont.cardHeading.font)
                        .foregroundStyle(HearthColor.ink(scheme))

                    Text("Safety alerts can't reach you")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                handleNotificationPermission()
            } label: {
                Text("Turn on")
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.onAccent(scheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(HearthColor.amber(scheme))
                    .clipShape(Capsule())
            }
        }
        .padding(HearthMetrics.pagePadding)
        .background(HearthColor.amberBg(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - Description Sections

    @ViewBuilder
    private var failureDescriptionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(HearthFont.iconMedium.font)
                .foregroundStyle(HearthColor.sub(scheme))

            Text("Tells you when the garage won't close, a lock won't lock or the alarm won't arm.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HearthMetrics.groupInset + 12)
    }

    @ViewBuilder
    private var retryDescriptionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(HearthFont.iconMedium.font)
                .foregroundStyle(HearthColor.sub(scheme))

            Text("Hearth tries again once before it tells you.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HearthMetrics.groupInset + 12)
    }

    // MARK: - Helpers

    private func handleNotificationPermission() {
        if notificationStatus == .notDetermined {
            Task {
                let granted = await HouseNotify.requestPermission()
                notificationStatus = granted ? .authorized : .denied
            }
        } else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Previews

#Preview("Enabled - Light") {
    NavigationStack {
        SafetyAlertsPage()
    }
    .preferredColorScheme(.light)
}

#Preview("Enabled - Dark") {
    NavigationStack {
        SafetyAlertsPage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Off - Light") {
    struct OffPreview: View {
        init() {
            HouseFeaturesStore.safetyEnabled = false
        }

        var body: some View {
            NavigationStack {
                SafetyAlertsPage()
            }
        }
    }
    return OffPreview()
        .preferredColorScheme(.light)
}

#Preview("Notifications Denied - Light") {
    struct DeniedPreview: View {
        init() {
            HouseFeaturesStore.safetyEnabled = true
        }

        var body: some View {
            NavigationStack {
                SafetyAlertsPage()
            }
        }
    }
    return DeniedPreview()
        .preferredColorScheme(.light)
}

#Preview("Notifications Denied - Dark") {
    struct DeniedPreview: View {
        init() {
            HouseFeaturesStore.safetyEnabled = true
        }

        var body: some View {
            NavigationStack {
                SafetyAlertsPage()
            }
        }
    }
    return DeniedPreview()
        .preferredColorScheme(.dark)
}
