import SwiftUI
import HearthKit
import UserNotifications

/// Morning commute auto-join settings page.
/// Enables the feature, shows sensor detection status, provides HA config YAML, and handles notification permissions.
@MainActor
struct MorningCommutePage: View {
    @State private var enabled: Bool
    @State private var checkBeforeLeaveEnabled: Bool
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var lastHeardDate: Date? = nil
    @State private var copiedSensor = false
    @State private var copiedAutomation = false

    @Environment(\.colorScheme) private var scheme

    init() {
        _enabled = State(initialValue: CommuteStore.enabled)
        _checkBeforeLeaveEnabled = State(initialValue: CommuteStore.checkBeforeLeaveEnabled)
        _lastHeardDate = State(initialValue: CommuteStore.lastHeard)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Two toggle rows in one card
                HearthGroup {
                    HearthRow(
                        icon: "figure.run",
                        hue: .blue,
                        title: "Auto-join on my commute",
                        subtitle: "Weekday mornings, when Home Assistant sees you ~30 min from work, Hearth joins in auto-run"
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

                    HearthRow(
                        icon: "checkmark.rectangle.portrait",
                        hue: .purple,
                        title: "Check before I leave",
                        subtitle: "At the door, asks you to sign in if Join would run out"
                    ) {
                        HearthSwitch(isOn: Binding(
                            get: { checkBeforeLeaveEnabled },
                            set: { newValue in
                                checkBeforeLeaveEnabled = newValue
                                CommuteStore.checkBeforeLeaveEnabled = newValue
                            }
                        ))
                    }
                }
                .padding(.top, 20)

                // Notifications denied banner
                if notificationStatus == .denied {
                    notificationsDeniedBanner
                }

                // Needed for Check before I leave section
                if checkBeforeLeaveEnabled {
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
        VStack(spacing: 16) {
            Text("Needed for Check before I leave")
                .font(HearthFont.groupLabel.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HearthMetrics.groupInset + 12)

            HearthGroup {
                HearthRow(
                    icon: "sensor",
                    hue: .green,
                    title: "Copy the sensor",
                    subtitle: sensorStatusText
                ) {
                    Button {
                        UIPasteboard.general.string = sensorYAML
                        copiedSensor = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedSensor = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Copy")
                                .font(HearthFont.button.font)
                        }
                        .foregroundStyle(HearthColor.ink(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(HearthColor.tint(scheme))
                        .clipShape(Capsule())
                    }
                }

                HearthRow(
                    icon: "arrow.triangle.turn.up.right.diamond",
                    hue: .green,
                    title: "Copy the automation",
                    subtitle: automationStatusText
                ) {
                    Button {
                        UIPasteboard.general.string = automationYAML
                        copiedAutomation = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedAutomation = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Copy")
                                .font(HearthFont.button.font)
                        }
                        .foregroundStyle(HearthColor.ink(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(HearthColor.tint(scheme))
                        .clipShape(Capsule())
                    }
                }
            }

            Text("Paste the sensor into configuration.yaml and the automation as a new automation. Nothing else is shared.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sensorStatusText: String {
        switch detectionStatus {
        case .found:
            return "Found in Home Assistant"
        case .lastHeard(let date):
            let formatter = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
            return "Last heard: today \(date.formatted(formatter))"
        case .waiting:
            return "Waiting for first read"
        }
    }

    private var automationStatusText: String {
        // For now, show found if sensor is found
        switch detectionStatus {
        case .found:
            return "Found in Home Assistant"
        case .lastHeard(let date):
            let formatter = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
            return "Last heard: today \(date.formatted(formatter))"
        case .waiting:
            return "Waiting for first read"
        }
    }


    // MARK: - HA YAML Templates

    private var sensorYAML: String {
        """
        template:
          - binary_sensor:
              - name: "Leaving home soon"
                unique_id: leaving_home_soon
                state: >
                  {% set door = states('binary_sensor.front_door_contact') %}
                  {{ door == 'on' }}
        """
    }

    private var automationYAML: String {
        """
        automation:
          - alias: "Check before leave reminder"
            trigger:
              - platform: state
                entity_id: binary_sensor.leaving_home_soon
                to: 'on'
            action:
              - service: notify.mobile_app
                data:
                  message: "Check if you need to sign in to ChargePoint"
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
