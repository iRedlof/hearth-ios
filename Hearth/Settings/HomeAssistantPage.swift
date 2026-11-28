import SwiftUI
import HearthKit

/// Home Assistant settings page — status-first pushed page that re-skins existing HA connection surfaces.
/// Reuses existing logic from SettingsView, HaSettingsSections, SignInView, entity pickers.
@MainActor
struct HomeAssistantPage: View {
    @State private var config: HaConfig?
    @State private var editScope: String?
    @State private var entityNames: [String: String] = [:]
    @State private var checking = false
    @State private var heroOverride: HeroPresentation?
    @State private var showSignIn = false
    @State private var showAddress = false
    @State private var showSignInExplainer = false
    @State private var showSignOutConfirm = false
    @State private var saveError: String?
    @State private var resetTask: Task<Void, Never>?

    let runtime: any SettingsRuntime
    let onChange: (HaConfig?) -> Void
    let initialReconnect: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(config: HaConfig?, runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         initialReconnect: Bool = false, onChange: @escaping (HaConfig?) -> Void) {
        _config = State(initialValue: config)
        self.runtime = runtime
        self.initialReconnect = initialReconnect
        self.onChange = onChange
        let current = runtime.loadHa()
        _editScope = State(initialValue: haSameConnection(current?.config, config) ? current?.scope : nil)
        _showSignIn = State(initialValue: initialReconnect)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connection Hero
                ConnectionHero(
                    presentation: effectivePresentation,
                    title: "Home Assistant",
                    detail: heroDetail
                ) {
                    ctaButton
                }
                .padding(.top, 20)
                .padding(.horizontal, HearthMetrics.groupInset)

                // Connection Group
                HearthGroup("Connection") {
                    Button {
                        showAddress = true
                    } label: {
                        HearthRow(
                            icon: "globe",
                            hue: .blue,
                            title: "Web address",
                            subtitle: config?.baseUrl ?? "Not set"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showSignInExplainer = true
                    } label: {
                        HearthRow(
                            icon: "shield",
                            hue: .green,
                            title: "Sign-in",
                            subtitle: "Home Assistant login · renews by itself"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Devices Group (only when connected)
                if let config, haSettingsReady(config) {
                    devicesGroup(config: config)
                }
            }
            .hearthContentAnimation(value: config?.baseUrl, reduceMotion: reduceMotion)
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Home Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNames() }
        .onAppear { synchronizeConfig() }
        .sheet(isPresented: $showSignIn) {
            NavigationStack {
                SignInView(initialURL: config?.baseUrl) {
                    config = runtime.loadHa()?.config
                    onChange(config)
                    showSignIn = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSignIn = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddress) {
            AddressSheet(
                currentURL: config?.baseUrl ?? "",
                runtime: runtime,
                onSave: { url in
                    showAddress = false
                    // Trigger the same connect flow as SettingsView
                    showSignIn = true
                }
            )
        }
        .sheet(isPresented: $showSignInExplainer) {
            SignInExplainerSheet(
                onSignOut: {
                    showSignInExplainer = false
                    showSignOutConfirm = true
                }
            )
        }
        .alert("Sign out of Home Assistant?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                signOutHa()
            }
        } message: {
            Text("Your widgets will stop updating until you sign in again.")
        }
        .alert("Couldn't save settings", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Hero Presentation

    private var effectivePresentation: HeroPresentation {
        if let override = heroOverride {
            return override
        }
        guard let config else {
            return haHeroPresentation(.notSetUp)
        }
        return haHeroPresentation(haConnectionStatus(config))
    }

    private var heroDetail: String {
        guard let config else {
            return "No server configured"
        }
        // Show the host (not title). Device/widget counts would require a discovery call.
        return prettyHost(config.baseUrl)
    }

    // MARK: - CTA Button

    @ViewBuilder
    private var ctaButton: some View {
        let status = config.map { haConnectionStatus($0) } ?? .notSetUp

        switch status {
        case .connected:
            Button {
                Task { await checkConnection() }
            } label: {
                HStack(spacing: 8) {
                    if checking {
                        ProgressView()
                            .tint(HearthColor.onAccent(scheme))
                    }
                    Text(checking ? "Checking…" : "Check connection")
                }
            }
            .hearthInk()
            .disabled(checking)

        case .needsSignIn:
            Button("Sign in again") {
                showSignIn = true
            }
            .hearthInk()

        case .notSetUp:
            Button("Connect") {
                showSignIn = true
            }
            .hearthInk()
        }
    }

    // MARK: - Check Connection

    private func checkConnection() async {
        guard let config, let editScope else { return }
        checking = true
        heroOverride = nil

        // Cancel any pending reset
        resetTask?.cancel()
        resetTask = nil

        do {
            _ = try await runtime.discoverHa(config: config, scope: editScope, purpose: .names)
            heroOverride = haHeroCheckOK()
            // Reset to normal after 2 seconds (cancellation-safe)
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                heroOverride = nil
                resetTask = nil
            }
        } catch {
            heroOverride = haHeroOffline()
        }
        checking = false
    }

    // MARK: - Devices Group

    @ViewBuilder
    private func devicesGroup(config: HaConfig) -> some View {
        HearthGroup("Devices") {
            entityRow(
                "Alarm panel",
                domain: "alarm_control_panel",
                allowNone: true,
                selection: config.entityId
            ) { e in
                try apply { $0.entityId = e.id }
            }

            entityRow(
                "Front door",
                domain: "lock",
                allowNone: true,
                selection: config.lockId
            ) { e in
                try apply { $0.lockId = e.id; $0.lockName = e.id.isEmpty ? "" : e.name }
            }

            // The Alarm card's second row. With nothing saved, the one cover in the old Doors
            // selection shows here as the garage (`garageSelectedID`).
            entityRow(
                "Garage door",
                domain: "cover",
                allowNone: true,
                selection: garageSelectedID(config) ?? "",
                garagesOnly: true
            ) { e in
                try apply { $0.garageId = e.id }
            }

            entityRow(
                "Thermostat",
                domain: "climate",
                allowNone: true,
                selection: config.climateId
            ) { e in
                try apply { $0.climateId = e.id }
            }

            entityRow(
                "Resume button",
                domain: "button",
                allowNone: true,
                selection: config.resumeId
            ) { e in
                try apply { $0.resumeId = e.id }
            }

            NavigationLink {
                MultiEntityPickerView(
                    config: config,
                    domains: ["sensor", "binary_sensor"],
                    title: "Room sensors",
                    selected: config.sensorIds,
                    runtime: runtime
                ) { ids in
                    try apply { $0.sensorsJson = encodeIds(ids) }
                }
            } label: {
                HearthRow(
                    icon: "thermometer",
                    hue: .red,
                    title: "Room sensors",
                    subtitle: config.sensorIds.isEmpty ? "None" : "\(config.sensorIds.count) selected"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MultiEntityPickerView(
                    config: config,
                    domains: ["light"],
                    title: "Always show",
                    selected: config.lightPins.sorted(),
                    runtime: runtime
                ) { ids in
                    try apply { $0.lightPinsJson = encodeIds(ids) }
                }
            } label: {
                HearthRow(
                    icon: "lightbulb",
                    hue: .amber,
                    title: "Lights",
                    subtitle: config.lightPins.isEmpty ? "None" : "\(config.lightPins.count) selected"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MultiEntityPickerView(
                    config: config,
                    domains: ["script"],
                    title: "Scripts",
                    selected: config.scriptIds,
                    limit: 6,
                    runtime: runtime
                ) { ids in
                    try apply { $0.scriptIdsJson = encodeIds(ids) }
                }
            } label: {
                HearthRow(
                    icon: "bolt",
                    hue: .purple,
                    title: "Quick",
                    subtitle: config.scriptIds.isEmpty ? "None" : "\(config.scriptIds.count) selected"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MultiEntityPickerView(
                    config: config,
                    domains: ["switch", "light", "fan", "input_boolean", "script"],
                    title: "Tiles",
                    selected: config.favouriteIds,
                    limit: 12,
                    runtime: runtime
                ) { ids in
                    try apply { $0.favouriteIdsJson = encodeIds(ids) }
                }
            } label: {
                HearthRow(
                    icon: "star",
                    hue: .orange,
                    title: "Favourites",
                    subtitle: config.favouriteIds.isEmpty ? "None" : "\(config.favouriteIds.count) selected"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MultiEntityPickerView(
                    config: config,
                    domains: ["cover", "binary_sensor", "lock"],
                    title: "Doors",
                    selected: config.doorIds,
                    doorsOnly: true,
                    runtime: runtime
                ) { ids in
                    try apply { $0 = settingDoorSelection($0, doorIdsJson: encodeIds(ids)) }
                }
            } label: {
                HearthRow(
                    icon: "door.left.hand.open",
                    hue: .neutral,
                    title: "Doors",
                    subtitle: config.doorIds.isEmpty ? "None" : "\(config.doorIds.count) selected"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Entity Row

    @ViewBuilder
    private func entityRow(
        _ title: String,
        domain: String,
        allowNone: Bool,
        selection: String,
        garagesOnly: Bool = false,
        onPick: @escaping (HaEntity) throws -> Void
    ) -> some View {
        let (icon, hue) = iconAndHue(for: domain)
        NavigationLink {
            EntityPickerView(
                config: config!,
                domain: domain,
                title: title,
                allowNone: allowNone,
                selected: selection,
                garagesOnly: garagesOnly,
                runtime: runtime,
                onPick: onPick
            )
        } label: {
            HearthRow(
                icon: icon,
                hue: hue,
                title: title,
                subtitle: selection.isEmpty ? "Not set" : (entityNames[selection] ?? selection)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconAndHue(for domain: String) -> (String, TileHue) {
        switch domain {
        case "alarm_control_panel":
            return ("shield.checkered", .red)
        case "lock":
            return ("lock", .blue)
        case "climate":
            return ("thermometer", .orange)
        case "button":
            return ("button.programmable", .purple)
        case "cover":
            return ("door.garage.closed", .blue)
        default:
            return ("circle", .neutral)
        }
    }

    // MARK: - Helper Functions

    private func loadNames() async {
        guard let config, config.hasAuth, entityNames.isEmpty,
              let discovery = try? await runtime.discoverHa(
                config: config,
                scope: editScope,
                purpose: .names
              ) else { return }
        entityNames = Dictionary(
            discovery.entities.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func synchronizeConfig() {
        guard let current = runtime.loadHa(),
              current.scope == editScope,
              let latest = current.config,
              haSameConnection(config, latest) else { return }
        config = latest
        onChange(latest)
    }

    private func apply(_ mutate: @escaping (inout HaConfig) -> Void) throws {
        guard let editScope,
              let next = try runtime.saveHaEdit(expectedScope: editScope, edit: .fields(mutate)) else {
            throw HaError("Your account changed. Reopen Settings to continue.")
        }
        config = next
        runtime.refreshWidgets(kinds: [])
        onChange(next)
    }

    private func signOutHa() {
        do {
            config = try runtime.saveHaEdit(expectedScope: runtime.loadHa()?.scope, edit: .signOut)
            runtime.refreshWidgets(kinds: [])
            onChange(config)
        } catch {
            saveError = friendlyError(error)
        }
    }

    private func encodeIds(_ ids: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ids),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func prettyHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }
}

// MARK: - Address Sheet

@MainActor
private struct AddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String

    let runtime: any SettingsRuntime
    let onSave: (String) -> Void

    init(currentURL: String, runtime: any SettingsRuntime, onSave: @escaping (String) -> Void) {
        _urlText = State(initialValue: currentURL)
        self.runtime = runtime
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://home.example.com", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Home Assistant URL")
                } footer: {
                    Text("Enter the web address of your Home Assistant server. Must start with https://")
                }
            }
            .navigationTitle("Web address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(urlText)
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Sign-in Explainer Sheet

@MainActor
private struct SignInExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(HearthFont.iconHero.font)
                            .foregroundStyle(HearthColor.green(scheme))

                        Text("About Sign-in")
                            .font(HearthFont.pageTitle.font)
                    }
                    .padding(.top, 20)

                    // Explanation
                    HearthGroup {
                        HearthRow(
                            icon: "checkmark.circle",
                            hue: .green,
                            title: "Secure authentication",
                            subtitle: "OAuth sign-in through your Home Assistant server"
                        )

                        HearthRow(
                            icon: "arrow.triangle.2.circlepath",
                            hue: .blue,
                            title: "Automatic renewal",
                            subtitle: "Session refreshes by itself — you won't need to sign in again"
                        )
                    }

                    HearthGroup {
                        HearthRow(
                            icon: "key",
                            hue: .purple,
                            title: "Use an access token",
                            subtitle: "Advanced: paste a long-lived access token from Home Assistant"
                        )
                    }

                    // Sign out button
                    Button("Sign out", role: .destructive) {
                        onSignOut()
                    }
                    .hearthInk()
                    .padding(.top, 20)
                }
                .padding(.horizontal, HearthMetrics.groupInset)
                .padding(.bottom, 20)
            }
            .background(HearthColor.page(scheme))
            .navigationTitle("Sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Connected - Light") {
    NavigationStack {
        HomeAssistantPage(
            config: HaConfig(
                baseUrl: "https://home.example.net",
                token: "",
                entityId: "alarm_control_panel.ha",
                refreshToken: "mock_token"
            ),
            runtime: LiveSettingsRuntime.shared
        ) { _ in }
    }
    .preferredColorScheme(.light)
}

#Preview("Connected - Dark") {
    NavigationStack {
        HomeAssistantPage(
            config: HaConfig(
                baseUrl: "https://home.example.net",
                token: "",
                entityId: "alarm_control_panel.ha",
                refreshToken: "mock_token"
            ),
            runtime: LiveSettingsRuntime.shared
        ) { _ in }
    }
    .preferredColorScheme(.dark)
}

#Preview("Needs Sign-in - Light") {
    NavigationStack {
        HomeAssistantPage(
            config: HaConfig(
                baseUrl: "https://home.example.net",
                token: "",
                entityId: ""
            ),
            runtime: LiveSettingsRuntime.shared
        ) { _ in }
    }
    .preferredColorScheme(.light)
}

#Preview("Not Set Up - Light") {
    NavigationStack {
        HomeAssistantPage(
            config: nil,
            runtime: LiveSettingsRuntime.shared
        ) { _ in }
    }
    .preferredColorScheme(.light)
}

#Preview("Not Set Up - Dark") {
    NavigationStack {
        HomeAssistantPage(
            config: nil,
            runtime: LiveSettingsRuntime.shared
        ) { _ in }
    }
    .preferredColorScheme(.dark)
}
