import SwiftUI
import HearthKit

/// Goodnight key settings page.
/// Enables the feature, shows what one tap does, and configures hours, arm mode, and keep-on lights.
@MainActor
struct GoodnightPage: View {
    @State private var config: GoodnightConfig
    @State private var hasAlarm: Bool
    @State private var showHomeAssistant = false
    @State private var showHoursPicker = false
    @State private var showArmModePicker = false
    @State private var showKeepOnPicker = false
    @State private var allLights: [String] = []

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .hearthContentAnimation(value: hasAlarm, reduceMotion: reduceMotion)
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Goodnight key")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHomeAssistant) {
            NavigationStack {
                HomeAssistantPage(config: HaConfigStore.load()) { next in
                    // Reload hasAlarm state when HA config changes
                    hasAlarm = next?.isComplete == true
                    if next?.isComplete == true {
                        showHomeAssistant = false
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showHomeAssistant = false
                            // Reload hasAlarm on dismiss
                            hasAlarm = HaConfigStore.load()?.isComplete == true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showHoursPicker) {
            HoursPickerSheet(
                startHour: config.startHour,
                endHour: config.endHour,
                onSave: { start, end in
                    config.startHour = start
                    config.endHour = end
                    GoodnightStore.save(config)
                    showHoursPicker = false
                }
            )
        }
        .sheet(isPresented: $showArmModePicker) {
            ArmModePickerSheet(
                armMode: config.armMode,
                onSave: { mode in
                    config.armMode = mode
                    GoodnightStore.save(config)
                    showArmModePicker = false
                }
            )
        }
        .sheet(isPresented: $showKeepOnPicker) {
            KeepOnLightsSheet(
                selectedLights: config.keepOnLights,
                allLights: allLights,
                onSave: { lights in
                    config.keepOnLights = lights
                    GoodnightStore.save(config)
                    showKeepOnPicker = false
                }
            )
        }
        .task {
            // Load available lights for keep-on picker
            await loadAvailableLights()
        }
    }

    // MARK: - Helpers

    private func loadAvailableLights() async {
        guard let haConfig = HaConfigStore.load(), haConfig.hasAuth else {
            allLights = []
            return
        }
        do {
            let client = HaClient(haConfig)
            let statesJson = try await client.allStatesJson()
            let entities = parseEntities(statesJson)
            allLights = entities.filter { $0.id.hasPrefix("light.") }.map(\.id)
        } catch {
            allLights = []
        }
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
                .font(HearthFont.iconLarge.font)
                .foregroundStyle(HearthColor.sub(scheme))

            Text("Uses the Home key on an Alarm widget")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                showHomeAssistant = true
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
        .padding(HearthMetrics.pagePadding)
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
                .font(HearthFont.iconMedium.font)
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
                Button {
                    showHoursPicker = true
                } label: {
                    HearthRow(
                        icon: "clock",
                        hue: .purple,
                        title: "Hours",
                        subtitle: hoursSubtitle
                    ) {
                        Image(systemName: "chevron.right")
                            .font(HearthFont.iconSmall.font.weight(.semibold))
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, HearthMetrics.dividerInset)

                // Arm mode row
                Button {
                    showArmModePicker = true
                } label: {
                    HearthRow(
                        icon: "shield.checkered",
                        hue: .blue,
                        title: "Arm mode",
                        subtitle: armModeSubtitle
                    ) {
                        Image(systemName: "chevron.right")
                            .font(HearthFont.iconSmall.font.weight(.semibold))
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hoursSubtitle: String {
        let calendar = Calendar.current
        let now = Date()

        // Convert hours to Date objects for formatting
        let startDate = calendar.date(bySettingHour: config.startHour, minute: 0, second: 0, of: now) ?? now
        let endDate = calendar.date(bySettingHour: config.endHour, minute: 0, second: 0, of: now) ?? now

        // Use Date.FormatStyle to honor user's 24-hour locale setting
        let formatter = Date.FormatStyle()
            .hour(.defaultDigits(amPM: .abbreviated))
            .locale(Locale.current)

        let startFormatted = startDate.formatted(formatter)
        let endFormatted = endDate.formatted(formatter)

        return "\(startFormatted)–\(endFormatted)"
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
                Button {
                    showKeepOnPicker = true
                } label: {
                    HearthRow(
                        icon: "lightbulb",
                        hue: .orange,
                        title: "Keep on",
                        subtitle: keepOnSubtitle
                    ) {
                        Image(systemName: "chevron.right")
                            .font(HearthFont.iconSmall.font.weight(.semibold))
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                }
                .buttonStyle(.plain)
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

// MARK: - Picker Sheets

@MainActor
private struct HoursPickerSheet: View {
    @State private var startHour: Int
    @State private var endHour: Int
    let onSave: (Int, Int) -> Void
    @Environment(\.colorScheme) private var scheme

    init(startHour: Int, endHour: Int, onSave: @escaping (Int, Int) -> Void) {
        _startHour = State(initialValue: startHour)
        _endHour = State(initialValue: endHour)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Start hour", selection: $startHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }

                Picker("End hour", selection: $endHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
            }
            .navigationTitle("Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(startHour, endHour)
                    }
                }
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let calendar = Calendar.current
        let now = Date()
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        return date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)))
    }
}

@MainActor
private struct ArmModePickerSheet: View {
    @State private var armMode: GoodnightArmMode
    let onSave: (GoodnightArmMode) -> Void
    @Environment(\.colorScheme) private var scheme

    init(armMode: GoodnightArmMode, onSave: @escaping (GoodnightArmMode) -> Void) {
        _armMode = State(initialValue: armMode)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Arm mode", selection: $armMode) {
                    Text("Night").tag(GoodnightArmMode.night)
                    Text("Home").tag(GoodnightArmMode.home)
                }
                .pickerStyle(.inline)

                Section {
                    Text("Night mode provides perimeter protection while allowing interior motion. Home mode is used if your panel doesn't support Night.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Arm mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(armMode)
                    }
                }
            }
        }
    }
}

@MainActor
private struct KeepOnLightsSheet: View {
    @State private var selectedLights: [String]
    let allLights: [String]
    let onSave: ([String]) -> Void
    @Environment(\.colorScheme) private var scheme

    init(selectedLights: [String], allLights: [String], onSave: @escaping ([String]) -> Void) {
        _selectedLights = State(initialValue: selectedLights)
        self.allLights = allLights
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                if allLights.isEmpty {
                    Text("No lights found. Make sure you're connected to Home Assistant.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(allLights, id: \.self) { lightId in
                        Button {
                            if selectedLights.contains(lightId) {
                                selectedLights.removeAll { $0 == lightId }
                            } else {
                                selectedLights.append(lightId)
                            }
                        } label: {
                            HStack {
                                Text(lightName(lightId))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedLights.contains(lightId) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Keep on at night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedLights)
                    }
                }
            }
        }
    }

    private func lightName(_ entityId: String) -> String {
        entityId.split(separator: ".").last.map { String($0).replacingOccurrences(of: "_", with: " ").capitalized } ?? entityId
    }
}

// No-alarm previews removed: they cannot inject state to force hasAlarm=false
// (hasAlarm comes from HaConfigStore.load()?.isComplete at runtime)
