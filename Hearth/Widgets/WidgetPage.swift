import SwiftUI
import HearthKit

/// Per-widget settings page template: pencil-editable title, preview mat, status line, Uses/Safety/Shows/
/// Every day/Look groups, and Remove instructional sheet. Reuses existing pickers and setters from HomeAssistantPage.
@MainActor
struct WidgetPage: View {
    let kind: HomeWidgetKind
    let config: HaConfig?
    let runtime: any SettingsRuntime
    let onChange: (HaConfig?) -> Void
    let onRoute: (HomeRoute) -> Void

    @State private var editScope: String?
    @State private var entityNames: [String: String] = [:]
    @State private var customName: String?
    @State private var showRename = false
    @State private var showRemove = false
    @State private var saveError: String?
    @State private var confirmWithBiometric: Bool

    // The widget's own current data: drawn in the preview, and read for health/freshness
    @StateObject private var preview = CardStylePreviewModel()
    @StateObject private var thermostat = ThermostatLiveModel()

    @Environment(\.colorScheme) private var scheme

    init(kind: HomeWidgetKind, config: HaConfig?, runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         onRoute: @escaping (HomeRoute) -> Void = { _ in },
         onChange: @escaping (HaConfig?) -> Void) {
        self.kind = kind
        self.config = config
        self.runtime = runtime
        self.onRoute = onRoute
        self.onChange = onChange
        let current = runtime.loadHa()
        _editScope = State(initialValue: haSameConnection(current?.config, config) ? current?.scope : nil)
        _customName = State(initialValue: WidgetNameStore.name(for: kind))
        _confirmWithBiometric = State(initialValue: config?.confirmWithBiometric ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Title with pencil
                titleSection

                // Preview mat
                previewMat

                // Status line
                statusSection

                // Uses group
                if isSetUp {
                    usesGroup
                }

                // Safety group (Alarm only)
                if kind == .alarm, isSetUp {
                    safetyGroup
                }

                // Shows group (Car only)
                if kind == .car, isSetUp {
                    showsGroup
                }

                // Every day group (Alarm/Lights)
                if (kind == .alarm || kind == .lights), isSetUp {
                    everyDayGroup
                }

                // Look group
                if isSetUp {
                    lookGroup
                }

                // Not-set-up card
                if !isSetUp {
                    notSetUpCard
                }

                // Remove row (only if set up)
                if isSetUp {
                    removeSection
                }
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNames() }
        .task(id: config) { await loadSnapshot() }
        .onDisappear { thermostat.close() }
        #if DEBUG
        // Render harness: open a sub-sheet at launch so the walker can capture it. Inert without
        // the launch argument.
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-widgetShowRename") { showRename = true }
            else if arguments.contains("-widgetShowRemove") { showRemove = true }
        }
        #endif
        .sheet(isPresented: $showRename) {
            renameSheet
        }
        .sheet(isPresented: $showRemove) {
            removeSheet
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

    // MARK: - Sections

    private var titleSection: some View {
        HStack {
            Text(displayName)
                .font(HearthFont.largeTitle.font)
                .foregroundStyle(HearthColor.ink(scheme))
            Button {
                showRename = true
            } label: {
                Image(systemName: "pencil")
                    .font(.title3)
                    .foregroundStyle(HearthColor.sub(scheme))
            }
            Spacer()
        }
        .padding(.horizontal, HearthMetrics.pagePadding)
        .padding(.top, 20)
    }

    /// The same live picture the Card style page draws: the person's own widget, in this widget's
    /// own Card style (else All cards'). A picture only, so its keys do not act from here.
    private var previewMat: some View {
        CardStylePreviewCard(kind: kind, data: liveData, thermostat: liveThermostat,
                             style: CardStyleStore.effectiveStyle(for: kind))
            .redacted(reason: previewSource == .loading ? .placeholder : [])
            // Centred at its real size; the card scales itself down on a narrower page.
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        .background(HearthColor.widgetPreviewBg(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, HearthMetrics.pagePadding)
    }

    private var statusSection: some View {
        Text(widgetPreviewCaption(previewSource, status: statusLine))
            .font(HearthFont.rowTitle.font)
            .foregroundStyle(isSetUp && health != .ok ? HearthColor.amber(scheme) : HearthColor.sub(scheme))
            .padding(.horizontal, HearthMetrics.pagePadding)
    }

    @ViewBuilder
    private var usesGroup: some View {
        switch kind {
        case .alarm:
            HearthGroup("Uses") {
                entityRow("Alarm panel", domain: "alarm_control_panel", selection: config?.entityId ?? "") { e in
                    try apply { $0.entityId = e.id }
                }
                entityRow("Front door", domain: "lock", allowNone: true, selection: config?.lockId ?? "") { e in
                    try apply { $0.lockId = e.id; $0.lockName = e.id.isEmpty ? "" : e.name }
                }
                entityRow("Garage door", domain: "cover", allowNone: true,
                          selection: config.flatMap(garageSelectedID) ?? "", garagesOnly: true) { e in
                    try apply { $0.garageId = e.id }
                }
            }

        case .thermostat:
            HearthGroup("Uses") {
                entityRow("Thermostat", domain: "climate", selection: config?.climateId ?? "") { e in
                    try apply { $0.climateId = e.id }
                }
                multiEntityRow("Room sensors", domains: ["sensor", "binary_sensor"], selected: config?.sensorIds ?? []) { ids in
                    try apply { $0.sensorsJson = encodeIds(ids) }
                }
            }

        case .car:
            HearthGroup("Uses") {
                groupNote {
                    Text("Your Tesla is auto-discovered from Home Assistant.")
                        .font(HearthFont.rowTitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                }
            }

        case .lights:
            HearthGroup("Uses") {
                multiEntityRow("Always show", domains: ["light"], selected: Array(config?.lightPins ?? [])) { ids in
                    try apply { $0.lightPinsJson = encodeIds(ids) }
                }
            }

        case .quick:
            HearthGroup("Uses") {
                multiEntityRow("Scripts", domains: ["script"], selected: config?.scriptIds ?? [], limit: 6) { ids in
                    try apply { $0.scriptIdsJson = encodeIds(ids) }
                }
            }

        case .favourites:
            HearthGroup("Uses") {
                multiEntityRow("Tiles", domains: ["switch", "light", "fan", "input_boolean", "script"],
                               selected: config?.favouriteIds ?? [], limit: 12) { ids in
                    try apply { $0.favouriteIdsJson = encodeIds(ids) }
                }
            }

        case .activity, .battery:
            HearthGroup("Uses") {
                multiEntityRow("Sensors", domains: ["sensor", "binary_sensor"], selected: config?.sensorIds ?? []) { ids in
                    try apply { $0.sensorsJson = encodeIds(ids) }
                }
            }

        case .chargePoint:
            HearthGroup("Uses") {
                groupNote {
                    Text("Your ChargePoint account is used for all charging stations.")
                        .font(HearthFont.rowTitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                }
            }
        }
    }

    private var safetyGroup: some View {
        HearthGroup("Safety") {
            Button {
                // Toggle confirmWith with immediate UI update
                confirmWithBiometric.toggle()
                try? apply { $0.confirmWith = confirmWithBiometric ? CONFIRM_BIOMETRIC : CONFIRM_DIALOG }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disarm & unlock")
                            .font(HearthFont.rowTitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))
                        Text("Hearth asks first")
                            .font(HearthFont.subtitle.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                    Spacer()
                    HearthSwitch(isOn: $confirmWithBiometric)
                }
                .padding(HearthMetrics.mediumPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var showsGroup: some View {
        HearthGroup("Shows") {
            groupNote {
                ForEach(Self.carShows, id: \.self) { labels in
                    HStack(spacing: HearthMetrics.smallPadding) {
                        ForEach(labels, id: \.self) { label in
                            Text(label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(HearthColor.tint(scheme))
                                .clipShape(Capsule())
                        }
                    }
                }
                Text("Tap the widget to open the Tesla app.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
            }
        }
    }

    /// What the Car widget shows, a row of chips each.
    private static let carShows = [["Charge", "Range", "Locks"], ["Doors", "Cabin", "Tyres"]]

    /// Words or chips in a group where its neighbours have rows: as wide as the group, inset
    /// like a `HearthRow`, so "Uses" and "Shows" line up with "Look" and the rest of the page.
    private func groupNote<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HearthMetrics.mediumPadding) { content() }
            .padding(.horizontal, HearthMetrics.rowSidePadding)
            .padding(.vertical, HearthMetrics.mediumPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var everyDayGroup: some View {
        HearthGroup("Every day") {
            Button {
                onRoute(.goodnight)
            } label: {
                HearthRow(
                    icon: "moon.fill",
                    hue: .purple,
                    title: "Goodnight key"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var lookGroup: some View {
        HearthGroup("Look") {
            Button {
                onRoute(.cardStyle(kind))
            } label: {
                HearthRow(
                    icon: "paintbrush.fill",
                    hue: .neutral,
                    title: "Card style",
                    subtitle: cardStyleEntrySubtitle(own: CardStyleStore.override(for: kind))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var notSetUpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(HearthColor.amber(scheme))
                Text(setupHeader)
                    .font(HearthFont.cardHeading.font)
                    .foregroundStyle(HearthColor.ink(scheme))
            }
            Text(setupInstructions)
                .font(HearthFont.rowTitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
        }
        .padding(16)
        .background(HearthColor.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, HearthMetrics.pagePadding)
    }

    private var removeSection: some View {
        Button {
            showRemove = true
        } label: {
            Text("Remove from home screen")
                .font(HearthFont.rowTitle.font)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .padding(.horizontal, HearthMetrics.pagePadding)
    }

    // MARK: - Sheets

    private var renameSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Widget name", text: Binding(
                    get: { customName ?? kind.displayName },
                    set: { customName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .padding()

                Text("Shown on Hearth home and in Card style. Starts as the device's name.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        customName = WidgetNameStore.name(for: kind)
                        showRename = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = customName?.trimmingCharacters(in: .whitespaces)
                        WidgetNameStore.setName(trimmed?.isEmpty == false ? trimmed : nil, for: kind)
                        customName = WidgetNameStore.name(for: kind)
                        showRename = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var removeSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "hand.tap.fill")
                    .font(HearthFont.heroLarge.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .padding(.top, 40)

                VStack(spacing: 12) {
                    Text("Long-press the widget on your home screen, then tap Remove Widget.")
                        .font(HearthFont.rowTitle.font)
                        .foregroundStyle(HearthColor.ink(scheme))
                        .multilineTextAlignment(.center)

                    Text("Your settings will stay saved if you add it back later.")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button("Got it") {
                    showRemove = false
                }
                .hearthInk()
                .padding(.horizontal, HearthMetrics.pagePadding)
                .padding(.bottom, 20)
            }
            .navigationTitle("Remove from home screen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Entity Rows

    @ViewBuilder
    private func entityRow(
        _ title: String,
        domain: String,
        allowNone: Bool = false,
        selection: String,
        garagesOnly: Bool = false,
        onPick: @escaping (HaEntity) throws -> Void
    ) -> some View {
        let (icon, hue) = iconAndHue(for: domain)
        let notFound = !selection.isEmpty && entityNames[selection] == nil
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
                subtitle: selection.isEmpty ? "Not set" : notFound ? "Not found · Pick another" : (entityNames[selection] ?? selection),
                subtitleWarn: notFound
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func multiEntityRow(
        _ title: String,
        domains: [String],
        selected: [String],
        limit: Int? = nil,
        onPick: @escaping ([String]) throws -> Void
    ) -> some View {
        let (icon, hue) = iconAndHue(for: domains.first ?? "")
        NavigationLink {
            MultiEntityPickerView(
                config: config!,
                domains: domains,
                title: title,
                selected: selected,
                limit: limit,
                runtime: runtime,
                onChange: onPick
            )
        } label: {
            HearthRow(
                icon: icon,
                hue: hue,
                title: title,
                subtitle: selected.isEmpty ? "None" : "\(selected.count) selected"
            )
        }
        .buttonStyle(.plain)
    }

    private func iconAndHue(for domain: String) -> (String, TileHue) {
        switch domain {
        case "alarm_control_panel": return ("shield.checkered", .red)
        case "lock": return ("lock", .blue)
        case "climate": return ("thermometer", .orange)
        case "sensor", "binary_sensor": return ("sensor", .neutral)
        case "light": return ("lightbulb", .amber)
        case "script": return ("bolt", .purple)
        case "switch", "fan", "input_boolean": return ("switch.2", .orange)
        case "cover": return ("door.garage.closed", .blue)
        default: return ("circle", .neutral)
        }
    }

    // MARK: - Widget Preview

    /// What the preview card draws: the person's own data, a placeholder while that loads, or a
    /// labelled example. A sample under "On your home screen" would read as their real state.
    private var previewSource: WidgetPreviewSource {
        switch kind {
        case .thermostat:
            // The Thermostat draws its saved reading; with none saved and none on its way, the sample.
            return widgetPreviewSource(isSetUp: isSetUp,
                                       supportsLive: thermostat.entry != nil || thermostat.checking,
                                       hasLiveData: thermostat.entry != nil)
        default:
            // Every other set-up widget loads its own data on this page (`loadSnapshot`).
            return widgetPreviewSource(isSetUp: isSetUp, supportsLive: true, hasLiveData: loaded != nil)
        }
    }

    /// What this page has read for its widget.
    private var loaded: CardStylePreviewData? { preview.data[kind] }
    private var car: CarSnapshot? { loaded?.car }
    private var alarm: AlarmSnapshot? { loaded?.alarm }
    private var cp: CpSnapshot? { loaded?.chargePoint }

    /// What the preview may draw as the person's own: nothing until the preview is live, so a
    /// widget that is not set up draws the labelled sample.
    private var liveData: CardStylePreviewData? { previewSource == .live ? loaded : nil }
    private var liveThermostat: ThermostatEntryPayload? { previewSource == .live ? thermostat.entry : nil }

    // MARK: - Helpers

    private var displayName: String {
        widgetDisplayName(custom: customName, kindDefault: kind.displayName)
    }

    private var isSetUp: Bool {
        guard let config else { return false }
        switch kind {
        case .alarm: return config.isComplete
        case .thermostat: return config.hasClimate
        case .car: return config.carReady
        case .lights: return !config.lightPins.isEmpty
        case .quick: return !config.scriptIds.isEmpty
        case .favourites: return !config.favouriteIds.isEmpty
        case .activity, .battery: return !config.sensorIds.isEmpty
        case .chargePoint: return (try? CpSessionStore.context().session.isSignedIn) == true
        }
    }

    private var health: WidgetHealth {
        if !isSetUp { return .setup }

        // Derive real health from live snapshots
        switch kind {
        case .car:
            if let car {
                return widgetHealth(stale: car.stale, error: car.error != nil,
                                  needsSettings: car.needsSettings, needsSignIn: car.needsSignIn)
            }
        case .alarm:
            if let alarm {
                return widgetHealth(stale: alarm.stale, error: alarm.error != nil,
                                  needsSettings: alarm.needsSettings, needsSignIn: alarm.needsSignIn)
            }
        case .thermostat:
            if let entry = thermostat.entry {
                let presentation = entry.presentation
                let thermostatError = presentation.recovery != .none
                return widgetHealth(stale: false, error: thermostatError,
                                  needsSettings: presentation.configuration != .ready,
                                  needsSignIn: presentation.configuration == .needsAuthentication)
            }
        case .chargePoint:
            if let cp {
                // CP snapshot doesn't have error/needsSettings/needsSignIn - infer from account
                let needsSignIn = cp.account == "Signed out" || cp.account == "Account unknown"
                return widgetHealth(stale: cp.stale, error: false,
                                  needsSettings: false, needsSignIn: needsSignIn)
            }
        default:
            // Other kinds: return ok if set up
            break
        }
        return .ok
    }

    private var statusLine: String {
        widgetPageStatus(health: health, fresh: freshness, isSetUp: isSetUp,
                         service: kind == .chargePoint ? "ChargePoint" : "Home Assistant")
    }

    private var freshness: String? {
        guard isSetUp else { return nil }

        // Derive freshness from live snapshots' checkedAt
        switch kind {
        case .car:
            return car?.checkedAt.isEmpty == false ? car?.checkedAt : nil
        case .alarm:
            return alarm?.checkedAt != "—" ? alarm?.checkedAt : nil
        case .thermostat:
            if let entry = thermostat.entry, let checkedAt = entry.presentation.room.checkedAt {
                return formatCheckedAt(checkedAt)
            }
        case .chargePoint:
            return cp?.checkedAt.isEmpty == false ? cp?.checkedAt : nil
        default:
            break
        }
        return nil
    }

    private func formatCheckedAt(_ date: Date) -> String {
        // Thread-safe Date.FormatStyle (project rule A7.5 / gotchas) — no per-call DateFormatter.
        date.formatted(.dateTime.hour().minute())
    }

    private var requiredSteps: Int {
        switch kind {
        case .alarm: 2  // Alarm panel + Front door (the garage is optional)
        case .thermostat: 1  // Thermostat
        case .car: 0  // Auto-discovered from Home Assistant — no manual step
        case .lights: 1  // Always show
        case .quick: 1  // Scripts
        case .favourites: 1  // Tiles
        case .activity, .battery: 1  // Sensors
        case .chargePoint: 1  // Sign in
        }
    }

    /// Honest, correctly pluralized setup header. Zero-step kinds (auto-discovered Car) don't claim
    /// a step count — they just prompt to finish adding the widget.
    private var setupHeader: String {
        switch requiredSteps {
        case 0: "Almost there"
        case 1: "Set up in 1 step"
        default: "Set up in \(requiredSteps) steps"
        }
    }

    private var setupInstructions: String {
        switch kind {
        case .alarm: "Choose your alarm panel and front door to get started."
        case .thermostat: "Choose your thermostat to get started."
        case .car: "Your Tesla is auto-discovered. Add it to your home screen."
        case .lights: "Choose which lights to always show."
        case .quick: "Choose up to 6 scripts for quick actions."
        case .favourites: "Choose up to 12 tiles for favourites."
        case .activity, .battery: "Choose which sensors to monitor."
        case .chargePoint: "Sign in to ChargePoint to get started."
        }
    }

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

    private func apply(_ mutate: @escaping (inout HaConfig) -> Void) throws {
        guard let editScope,
              let next = try runtime.saveHaEdit(expectedScope: editScope, edit: .fields(mutate)) else {
            throw HaError("Your account changed. Reopen Settings to continue.")
        }
        // Sync confirmWithBiometric state
        confirmWithBiometric = next.confirmWithBiometric
        runtime.refreshWidgets(kinds: [])
        onChange(next)
    }

    /// Reads the widget's own current data, again whenever its settings change.
    private func loadSnapshot() async {
        guard isSetUp else { return }
        if kind == .thermostat {
            thermostat.loadCache()
        } else {
            await preview.reload(kind, config: config)
        }
    }

    private func encodeIds(_ ids: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ids),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
}

#Preview("Thermostat (set up)") {
    NavigationStack {
        WidgetPage(
            kind: .thermostat,
            config: HaConfig(baseUrl: "https://ha.local", token: "test", entityId: "alarm.test",
                             climateId: "climate.living_room"),
            onChange: { _ in }
        )
    }
}

#Preview("Alarm (not set up)") {
    NavigationStack {
        WidgetPage(
            kind: .alarm,
            config: HaConfig(baseUrl: "https://ha.local", token: "test", entityId: ""),
            onChange: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Car") {
    NavigationStack {
        WidgetPage(
            kind: .car,
            config: HaConfig(baseUrl: "https://ha.local", token: "test", entityId: "alarm.test"),
            onChange: { _ in }
        )
    }
}
