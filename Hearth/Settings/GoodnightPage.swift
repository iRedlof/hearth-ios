import SwiftUI
import HearthKit

/// Goodnight key settings page.
/// Enables the feature, shows what one tap does, and configures hours, arm mode, and keep-on lights.
@MainActor
struct GoodnightPage: View {
    @State private var config: GoodnightConfig
    @State private var hasAlarm: Bool

    @Environment(\.colorScheme) private var scheme

    init() {
        let loaded = GoodnightStore.load()
        _config = State(initialValue: loaded)
        _hasAlarm = State(initialValue: HaConfigStore.load()?.isComplete == true)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Enable toggle
                HearthGroup("Goodnight key") {
                    HearthRow(
                        icon: "moon.stars",
                        hue: .purple,
                        title: "Goodnight key",
                        subtitle: toggleSubtitle
                    ) {
                        HearthSwitch(isOn: Binding(
                            get: { config.enabled },
                            set: { newValue in
                                config.enabled = newValue
                                GoodnightStore.save(config)
                            }
                        ))
                    }
                }
                .padding(.top, 20)

                // No alarm banner (when alarm not configured)
                if goodnightPageState(hasAlarm: hasAlarm) == .noAlarm {
                    noAlarmBanner
                }

                // Explanatory "One tap does" section (always visible per 5b lesson)
                oneTapDoesSection

                // Configuration groups (only when alarm is configured)
                if goodnightPageState(hasAlarm: hasAlarm) == .ready {
                    whenGroup
                    keepOnGroup
                    footerText
                }
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Goodnight key")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Toggle Subtitle

    private var toggleSubtitle: String {
        if !config.enabled {
            return "Off"
        }
        if !hasAlarm {
            return "On"
        }
        return "On · Home alarm's Home key"
    }

    // MARK: - No Alarm Banner

    @ViewBuilder
    private var noAlarmBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: HearthMetrics.iconLarge))
                .foregroundStyle(HearthColor.sub(scheme))

            Text("Uses the Home key on an Alarm widget")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                // Navigate to Alarm widget setup
                // For now, just a placeholder
            } label: {
                Text("Add Alarm")
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.onAccent(scheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(HearthColor.amber(scheme))
                    .clipShape(Capsule())
            }
        }
        .padding(20)
        .background(HearthColor.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - One Tap Does Section

    @ViewBuilder
    private var oneTapDoesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One tap on the Home key does")
                .font(HearthFont.groupLabel.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)

            HStack(spacing: 20) {
                actionIcon("garage.closed", label: "Close garage")
                actionIcon("lightbulb.slash", label: "Lights off")
                actionIcon("lock", label: "Lock")
                actionIcon("shield.checkered", label: "Arm Night")
            }
            .padding(.horizontal, HearthMetrics.groupInset + 12)
        }
    }

    @ViewBuilder
    private func actionIcon(_ systemName: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: HearthMetrics.iconMedium))
                .foregroundStyle(HearthColor.sub(scheme))
                .frame(width: HearthMetrics.iconTile, height: HearthMetrics.iconTile)
                .background(HearthColor.tint(scheme))
                .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.iconTileRadius))

            Text(label)
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - When Group

    @ViewBuilder
    private var whenGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHEN")
                .font(HearthFont.groupLabel.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)

            HearthGroup {
                // Hours row
                HearthRow(
                    icon: "clock",
                    hue: .purple,
                    title: "Hours",
                    subtitle: hoursSubtitle
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: HearthMetrics.iconSmall, weight: .semibold))
                        .foregroundStyle(HearthColor.sub(scheme))
                }

                Divider()
                    .padding(.leading, HearthMetrics.dividerInset)

                // Arm mode row
                HearthRow(
                    icon: "shield.checkered",
                    hue: .blue,
                    title: "Arm mode",
                    subtitle: armModeSubtitle
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: HearthMetrics.iconSmall, weight: .semibold))
                        .foregroundStyle(HearthColor.sub(scheme))
                }
            }
        }
    }

    private var hoursSubtitle: String {
        let startHour = config.startHour
        let endHour = config.endHour

        func formatHour(_ hour: Int) -> String {
            let period = hour < 12 ? "AM" : "PM"
            let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            return "\(displayHour) \(period)"
        }

        return "\(formatHour(startHour))–\(formatHour(endHour))"
    }

    private var armModeSubtitle: String {
        switch config.armMode {
        case .night:
            return "Night (Home if the panel has no Night)"
        case .home:
            return "Home"
        }
    }

    // MARK: - Keep On Group

    @ViewBuilder
    private var keepOnGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KEEP ON AT NIGHT")
                .font(HearthFont.groupLabel.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)

            HearthGroup {
                HearthRow(
                    icon: "lightbulb",
                    hue: .orange,
                    title: "Keep on",
                    subtitle: keepOnSubtitle
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: HearthMetrics.iconSmall, weight: .semibold))
                        .foregroundStyle(HearthColor.sub(scheme))
                }
            }
        }
    }

    private var keepOnSubtitle: String {
        if config.keepOnLights.isEmpty {
            return "No lights"
        }
        // Extract light name from entity ID (e.g., "light.porch" → "Porch")
        let names = config.keepOnLights.map { entityId in
            entityId.split(separator: ".").last.map { String($0).capitalized } ?? entityId
        }
        return names.joined(separator: ", ")
    }

    // MARK: - Footer Text

    @ViewBuilder
    private var footerText: some View {
        Text("Works from the lock screen. A learned routine that does the same is shown as \"Same as Goodnight key\".")
            .font(HearthFont.subtitle.font)
            .foregroundStyle(HearthColor.sub(scheme))
            .padding(.horizontal, HearthMetrics.groupInset + 12)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Previews

#Preview("Configured - On - Light") {
    NavigationStack {
        GoodnightPage()
    }
    .preferredColorScheme(.light)
    .onAppear {
        GoodnightStore.save(GoodnightConfig(
            enabled: true,
            startHour: 21,
            endHour: 5,
            armMode: .night,
            keepOnLights: ["light.porch"]
        ))
    }
}

#Preview("Configured - On - Dark") {
    NavigationStack {
        GoodnightPage()
    }
    .preferredColorScheme(.dark)
    .onAppear {
        GoodnightStore.save(GoodnightConfig(
            enabled: true,
            startHour: 21,
            endHour: 5,
            armMode: .night,
            keepOnLights: ["light.porch"]
        ))
    }
}

#Preview("Configured - Off - Light") {
    NavigationStack {
        GoodnightPage()
    }
    .preferredColorScheme(.light)
    .onAppear {
        GoodnightStore.save(GoodnightConfig(
            enabled: false,
            startHour: 21,
            endHour: 5,
            armMode: .night,
            keepOnLights: ["light.porch"]
        ))
    }
}

#Preview("No Alarm - Light") {
    struct NoAlarmPreview: View {
        init() {
            // Simulate no alarm configured
            // In real app, hasAlarm comes from HaConfigStore.load()?.isComplete
        }

        var body: some View {
            NavigationStack {
                GoodnightPage()
            }
        }
    }
    return NoAlarmPreview()
        .preferredColorScheme(.light)
}

#Preview("No Alarm - Dark") {
    struct NoAlarmPreview: View {
        init() {
            // Simulate no alarm configured
            // In real app, hasAlarm comes from HaConfigStore.load()?.isComplete
        }

        var body: some View {
            NavigationStack {
                GoodnightPage()
            }
        }
    }
    return NoAlarmPreview()
        .preferredColorScheme(.dark)
}
