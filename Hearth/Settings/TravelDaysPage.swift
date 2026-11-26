import SwiftUI
import HearthKit
import EventKit

/// Travel days settings page — trip notifications.
/// Enables the feature, shows next upcoming trip, and handles calendar permissions.
@MainActor
struct TravelDaysPage: View {
    @State private var enabled: Bool
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    @State private var nextTripText: String = "No trips in the next 7 days"

    @Environment(\.colorScheme) private var scheme

    init() {
        _enabled = State(initialValue: HouseFeaturesStore.travelEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Enable toggle
                HearthGroup("Travel days") {
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
                            }
                        ))
                    }
                }
                .padding(.top, 20)

                // Calendar permission banners
                let bannerState = calendarBannerState(enabled: enabled, calendarStatus: calendarStatus.rawValue)
                if bannerState == .needsPermission {
                    calendarDeniedBanner
                } else if bannerState == .restricted {
                    calendarRestrictedBanner
                }

                if enabled {
                    // Description sections
                    tripDefinitionSection
                    notificationTimeSection
                    confirmationSection
                    privacySection
                }
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Travel days")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            calendarStatus = CalendarAccess().authorizationStatus()
            await loadNextTrip()
        }
    }

    // MARK: - Subtitle

    private var subtitleText: String {
        guard enabled else { return "Off" }
        return nextTripText
    }

    // MARK: - Calendar Denied Banner

    @ViewBuilder
    private var calendarDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: HearthMetrics.iconLarge))
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
                    .font(.system(size: HearthMetrics.iconLarge))
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

    // MARK: - Description Sections

    @ViewBuilder
    private var tripDefinitionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: HearthMetrics.iconMedium))
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
                .font(.system(size: HearthMetrics.iconMedium))
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
                .font(.system(size: HearthMetrics.iconMedium))
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
                .font(.system(size: HearthMetrics.iconMedium))
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
