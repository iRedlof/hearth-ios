import SwiftUI
import HearthKit
import UserNotifications

/// Morning commute auto-join settings page.
/// Enables the feature, shows sensor detection status, provides HA config YAML, and handles notification permissions.
@MainActor
struct MorningCommutePage: View {
    @State private var enabled: Bool
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var lastHeardDate: Date? = nil
    @State private var copiedChargeNow = false
    @State private var copiedSignIn = false

    @Environment(\.colorScheme) private var scheme

    init() {
        _enabled = State(initialValue: CommuteStore.enabled)
        _lastHeardDate = State(initialValue: CommuteStore.lastHeard)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Enable toggle
                HearthGroup("Morning Commute") {
                    HearthRow(
                        icon: "sunrise",
                        hue: .orange,
                        title: "Auto-join on commute",
                        subtitle: "Arms waitlist when approaching office"
                    ) {
                        HearthSwitch(isOn: Binding(
                            get: { enabled },
                            set: { newValue in
                                enabled = newValue
                                CommuteStore.enabled = newValue

                                // Request notification permission when enabling (if not determined)
                                if newValue && notificationStatus == .notDetermined {
                                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                                        Task { @MainActor in
                                            await refreshNotificationStatus()
                                        }
                                    }
                                }
                            }
                        ))
                    }
                }
                .padding(.top, 20)

                // Detection status
                if enabled {
                    HearthGroup("Detection") {
                        HearthRow(
                            icon: "sensor",
                            hue: .purple,
                            title: "Sensor status",
                            subtitle: detectionSubtitle
                        ) {
                            detectionPill
                        }
                    }
                }

                // Notifications denied banner
                if notificationStatus == .denied {
                    notificationsDeniedBanner
                }

                // HA config sections
                if enabled {
                    haConfigSection
                }
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Morning Commute")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshNotificationStatus()
            lastHeardDate = CommuteStore.lastHeard
        }
    }

    // MARK: - Detection Status

    private var detectionStatus: CommuteStatus {
        commuteStatus(lastHeard: lastHeardDate, now: Date())
    }

    private var detectionSubtitle: String {
        switch detectionStatus {
        case .found:
            return "Sensor active"
        case .lastHeard(let date):
            let formatter = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
            return "Last heard \(date.formatted(formatter))"
        case .waiting:
            return "Waiting for first sensor read"
        }
    }

    @ViewBuilder
    private var detectionPill: some View {
        switch detectionStatus {
        case .found:
            StatusPill("Found", tone: .ok)
        case .lastHeard:
            StatusPill("Stale", tone: .neutral)
        case .waiting:
            StatusPill("Waiting", tone: .warn)
        }
    }

    // MARK: - Notifications Denied Banner

    @ViewBuilder
    private var notificationsDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(HearthColor.amber(scheme))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications disabled")
                        .font(HearthFont.cardHeading.font)
                        .foregroundStyle(HearthColor.ink(scheme))

                    Text("Enable notifications to receive sign-in reminders when your ChargePoint session expires during your commute.")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
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

    // MARK: - HA Config Section

    @ViewBuilder
    private var haConfigSection: some View {
        VStack(spacing: 20) {
            // Charge Now sensor
            VStack(alignment: .leading, spacing: 12) {
                Text("HOME ASSISTANT CONFIG")
                    .font(HearthFont.groupLabel.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .padding(.horizontal, HearthMetrics.groupInset + 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Charge Now Sensor")
                        .font(HearthFont.cardHeading.font)
                        .foregroundStyle(HearthColor.ink(scheme))

                    Text("Triggers auto-join when ETA ≤ 30 min on weekday mornings (09:00–11:00).")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    yamlBlock(chargeNowYAML)

                    Button {
                        UIPasteboard.general.string = chargeNowYAML
                        copiedChargeNow = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedChargeNow = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copiedChargeNow ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                            Text(copiedChargeNow ? "Copied" : "Copy YAML")
                                .font(HearthFont.rowTitle.font)
                        }
                        .foregroundStyle(copiedChargeNow ? HearthColor.green(scheme) : HearthColor.ink(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(copiedChargeNow ? HearthColor.greenBg(scheme) : HearthColor.tint(scheme))
                        .clipShape(Capsule())
                    }
                }
                .padding(20)
                .background(HearthColor.card(scheme))
                .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
                .padding(.horizontal, HearthMetrics.groupInset)
            }

            // Sign-in Needed sensor
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("2. Sign-in Needed Sensor")
                        .font(HearthFont.cardHeading.font)
                        .foregroundStyle(HearthColor.ink(scheme))

                    Text("Notifies you to sign in when ETA ≤ 45 min (earlier margin for re-auth).")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    yamlBlock(signInNeededYAML)

                    Button {
                        UIPasteboard.general.string = signInNeededYAML
                        copiedSignIn = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedSignIn = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copiedSignIn ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                            Text(copiedSignIn ? "Copied" : "Copy YAML")
                                .font(HearthFont.rowTitle.font)
                        }
                        .foregroundStyle(copiedSignIn ? HearthColor.green(scheme) : HearthColor.ink(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(copiedSignIn ? HearthColor.greenBg(scheme) : HearthColor.tint(scheme))
                        .clipShape(Capsule())
                    }
                }
                .padding(20)
                .background(HearthColor.card(scheme))
                .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
                .padding(.horizontal, HearthMetrics.groupInset)
            }

            // Installation note
            Text("Add these sensors to your Home Assistant configuration (config/templates.yaml or a package), then reload Template Entities.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func yamlBlock(_ yaml: String) -> some View {
        Text(yaml)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(HearthColor.ink(scheme))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HearthColor.tint(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - HA YAML Templates

    private var chargeNowYAML: String {
        """
        template:
          - binary_sensor:
              - name: "Commute charge now"
                unique_id: commute_charge_now
                state: >
                  {% set eta = states('sensor.waze_commute_to_work') | float(none) %}
                  {% set in_window = now().weekday() < 5 and 9 <= now().hour < 11 %}
                  {% set away = states('person.rohit_chandani') != 'home' %}
                  {{ in_window and away and eta is not none and 0 < eta <= 30 }}
        """
    }

    private var signInNeededYAML: String {
        """
        template:
          - binary_sensor:
              - name: "Commute signin needed"
                unique_id: commute_signin_needed
                state: >
                  {% set eta = states('sensor.waze_commute_to_work') | float(none) %}
                  {% set in_window = now().weekday() < 5 and 9 <= now().hour < 11 %}
                  {% set away = states('person.rohit_chandani') != 'home' %}
                  {{ in_window and away and eta is not none and 0 < eta <= 45 }}
        """
    }

    // MARK: - Helpers

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }
}

// MARK: - Previews

#Preview("Enabled - Light") {
    NavigationStack {
        MorningCommutePage()
    }
    .preferredColorScheme(.light)
}

#Preview("Enabled - Dark") {
    NavigationStack {
        MorningCommutePage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Notifications Denied - Light") {
    struct DeniedPreview: View {
        var body: some View {
            NavigationStack {
                MorningCommutePage()
                    .task {
                        // Simulate denied state
                        // In real app, this comes from UNUserNotificationCenter
                    }
            }
        }
    }
    return DeniedPreview()
        .preferredColorScheme(.light)
}

#Preview("Waiting State - Dark") {
    NavigationStack {
        MorningCommutePage()
    }
    .preferredColorScheme(.dark)
}
