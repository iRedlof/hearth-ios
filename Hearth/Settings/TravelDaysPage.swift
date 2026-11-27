import SwiftUI
import HearthKit
import EventKit
import UserNotifications

/// Travel days settings page — trip notifications.
/// Enables the feature, shows next upcoming trip, and handles calendar and notification permissions.
@MainActor
struct TravelDaysPage: View {
    @State private var enabled: Bool
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var nextTripText: String = "No trips in the next 7 days"

    @Environment(\.colorScheme) private var scheme

    init() {
        _enabled = State(initialValue: HouseFeaturesStore.travelEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Travel days")
                    .font(HearthFont.pageTitle.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                Text("Asks before a trip on your calendar")
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
                            icon: "calendar",
                            hue: .neutral,
                            title: "Travel days",
                            subtitle: enabled ? subtitleText : "Off"
                        ) {
                            HearthSwitch(isOn: Binding(
                                get: { enabled },
                                set: { newValue in
                                    enabled = newValue
                                    HouseFeaturesStore.travelEnabled = newValue

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

                    // Description sections (3 icon bullets)
                    tripDefinitionSection
                    notificationTimeSection
                    confirmationSection

                    // Privacy note
                    privacySection
                }
                .padding(.bottom, 20)
            }
        }
        .background(HearthColor.page(scheme))
        .task {
            calendarStatus = CalendarAccess().authorizationStatus()
            notificationStatus = await HouseNotify.authorizationStatus()
            await loadNextTrip()
        }
    }

    // MARK: - Subtitle

    private var subtitleText: String {
        guard enabled else { return "Off" }
        return nextTripText
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

                    Text("Travel days can't reach you")
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
        .padding(HearthMetrics.pagePadding)
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
        .padding(HearthMetrics.pagePadding)
        .background(HearthColor.amberBg(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - Description Sections

    @ViewBuilder
    private var tripDefinitionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(HearthFont.iconMedium.font)
                .foregroundStyle(HearthColor.sub(scheme))

            Text("A trip is an all-day event, or one 24 h or longer, in the next 7 days.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HearthMetrics.groupInset + 12)
    }

    @ViewBuilder
    private var notificationTimeSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(HearthFont.iconMedium.font)
                .foregroundStyle(HearthColor.sub(scheme))

            Text("At 8 PM the night before, Hearth offers: arm Away, thermostat low.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HearthMetrics.groupInset + 12)
    }

    @ViewBuilder
    private var confirmationSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(HearthFont.iconMedium.font)
                .foregroundStyle(HearthColor.sub(scheme))

            Text("Nothing runs until you confirm.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HearthMetrics.groupInset + 12)
    }

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
                if granted {
                    await loadNextTrip()
                }
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

    private func loadNextTrip() async {
        guard calendarStatus == .authorized else {
            nextTripText = "No trips in the next 7 days"
            return
        }

        let events = await CalendarAccess().upcomingEvents(days: 7)
        let trips = travelTrips(events: events, now: Date(), calendar: .current)
        nextTripText = nextTripSubtitle(trips: trips, now: Date())
    }
}

// MARK: - Previews

#Preview("Enabled with Trip - Light") {
    NavigationStack {
        TravelDaysPage()
    }
    .preferredColorScheme(.light)
}

#Preview("Enabled with Trip - Dark") {
    NavigationStack {
        TravelDaysPage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Off - Light") {
    struct OffPreview: View {
        init() {
            HouseFeaturesStore.travelEnabled = false
        }

        var body: some View {
            NavigationStack {
                TravelDaysPage()
            }
        }
    }
    return OffPreview()
        .preferredColorScheme(.light)
}

#Preview("Calendar Denied - Light") {
    struct DeniedPreview: View {
        init() {
            HouseFeaturesStore.travelEnabled = true
        }

        var body: some View {
            NavigationStack {
                TravelDaysPage()
            }
        }
    }
    return DeniedPreview()
        .preferredColorScheme(.light)
}

#Preview("Calendar Denied - Dark") {
    struct DeniedPreview: View {
        init() {
            HouseFeaturesStore.travelEnabled = true
        }

        var body: some View {
            NavigationStack {
                TravelDaysPage()
            }
        }
    }
    return DeniedPreview()
        .preferredColorScheme(.dark)
}
