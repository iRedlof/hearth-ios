import SwiftUI
import HearthKit
import EventKit
import UserNotifications

/// Leave-by settings page — checks before you go.
/// Enables the feature, sets minutes-before timing, shows privacy notes, and handles calendar and notification permissions.
@MainActor
struct LeaveByPage: View {
    @State private var enabled: Bool
    @State private var minutesBefore: Int
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let minutesOptions = [10, 15, 20, 30, 45, 60]

    init() {
        _enabled = State(initialValue: HouseFeaturesStore.leaveByEnabled)
        _minutesBefore = State(initialValue: HouseFeaturesStore.leaveByMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Leave-by")
                    .font(HearthFont.pageTitle.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                Text("Checks the house before you go")
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
                            icon: "figure.walk",
                            hue: .neutral,
                            title: "Leave-by",
                            subtitle: enabled ? "On" : "Off"
                        ) {
                            HearthSwitch(isOn: Binding(
                                get: { enabled },
                                set: { newValue in
                                    enabled = newValue
                                    HouseFeaturesStore.leaveByEnabled = newValue

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

                    // Description
                    HStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .font(HearthFont.iconMedium.font)
                            .foregroundStyle(HearthColor.sub(scheme))

                        Text("Checks Home alarm, Front door and Hallway thermostat. Asks before it arms, locks or sets Eco; nothing runs until you confirm.")
                            .font(HearthFont.subtitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, HearthMetrics.groupInset + 12)

                    // Minutes before chips (only when enabled)
                    if enabled {
                        minutesBeforeSection
                    }

                    // Privacy note (always show)
                    privacySection
                }
                .hearthContentAnimation(value: enabled, reduceMotion: reduceMotion)
                .padding(.bottom, 20)
            }
        }
        .background(HearthColor.page(scheme))
        .task {
            calendarStatus = CalendarAccess().authorizationStatus()
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

                    Text("Leave-by can't reach you")
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
        .padding(20)
        .background(HearthColor.amberBg(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - Calendar Denied Banner

    @ViewBuilder
    private var calendarDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(HearthFont.iconLarge.font)
                    .foregroundStyle(HearthColor.amber(scheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs calendar access")
                        .font(HearthFont.cardHeading.font)
                        .foregroundStyle(HearthColor.ink(scheme))

                    Text("Hearth reads event times and places")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                handleCalendarPermission()
            } label: {
                Text("Allow")
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.onAccent(scheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(HearthColor.amber(scheme))
                    .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(HearthColor.amberBg(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - Calendar Restricted Banner

    @ViewBuilder
    private var calendarRestrictedBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.lock")
                    .font(HearthFont.iconLarge.font)
                    .foregroundStyle(HearthColor.amber(scheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar access is restricted")
                        .font(HearthFont.cardHeading.font)
                        .foregroundStyle(HearthColor.ink(scheme))

                    Text("Screen Time or parental controls prevent calendar access. This setting cannot be changed.")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(HearthColor.amberBg(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - Description Section

    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(HearthFont.iconMedium.font)
                    .foregroundStyle(HearthColor.sub(scheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Checks Home alarm, Front door and Hallway thermostat.")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Asks before it arms, locks or sets Eco; nothing runs until you confirm.")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(HearthColor.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - Minutes Before Section

    @ViewBuilder
    private var minutesBeforeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Minutes before it starts · Dentist 3:00 → check 2:40")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ForEach(minutesOptions, id: \.self) { minutes in
                    Button {
                        minutesBefore = minutes
                        HouseFeaturesStore.leaveByMinutes = minutes
                    } label: {
                        Text(minutes == 60 ? "60 min" : "\(minutes)")
                            .font(HearthFont.button.font)
                            .foregroundStyle(minutesBefore == minutes ? HearthColor.onAccent(scheme) : HearthColor.ink(scheme))
                            .frame(minWidth: 44, minHeight: 44)
                            .background(minutesBefore == minutes ? HearthColor.ink(scheme) : HearthColor.tint(scheme))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, HearthMetrics.groupInset + 12)
        }
    }

    // MARK: - Privacy Section

    @ViewBuilder
    private var privacySection: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(HearthFont.iconMedium.font)
                .foregroundStyle(HearthColor.sub(scheme))

            Text("Reads your calendar on this phone only. Nothing leaves the device.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HearthMetrics.groupInset + 12)
    }

    // MARK: - Helpers

    private func handleCalendarPermission() {
        // .restricted cannot be changed by the user
        if calendarStatus == .restricted {
            return
        }

        if calendarStatus == .notDetermined {
            Task {
                let granted = await CalendarAccess().requestAccess()
                calendarStatus = granted ? .authorized : .denied
            }
        } else if calendarStatus == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

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
        LeaveByPage()
    }
    .preferredColorScheme(.light)
}

#Preview("Enabled - Dark") {
    NavigationStack {
        LeaveByPage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Off - Light") {
    struct OffPreview: View {
        init() {
            HouseFeaturesStore.leaveByEnabled = false
        }

        var body: some View {
            NavigationStack {
                LeaveByPage()
            }
        }
    }
    return OffPreview()
        .preferredColorScheme(.light)
}

#Preview("Calendar Denied - Light") {
    struct DeniedPreview: View {
        init() {
            HouseFeaturesStore.leaveByEnabled = true
        }

        var body: some View {
            NavigationStack {
                LeaveByPage()
            }
        }
    }
    return DeniedPreview()
        .preferredColorScheme(.light)
}

#Preview("Calendar Denied - Dark") {
    struct DeniedPreview: View {
        init() {
            HouseFeaturesStore.leaveByEnabled = true
        }

        var body: some View {
            NavigationStack {
                LeaveByPage()
            }
        }
    }
    return DeniedPreview()
        .preferredColorScheme(.dark)
}
