#if DEBUG
import SwiftUI
import HearthKit

enum SettingsFixtureCase: String, CaseIterable {
    case fresh, chargepointOnly, haWithoutAlarm, haExpired
    case pickerMissing, pickerOverLimit, discoveryFailed
}

/// Read counters do not publish during View initialization. Action/discovery changes publish so the
/// visible ledger follows the same production controls and their persisted in-memory outcomes.
@MainActor
final class SettingsFixtureEffects: ObservableObject {
    @Published private(set) var revision = 0
    private var operations: [String: Int] = [:]
    private var live: [String: Int] = [:]
    private var events: [String] = []

    private let liveNames = [
        "transport", "storeReads", "storeWrites", "scheduler",
        "notifications", "timelines", "URL", "auth", "appUpdater"
    ]

    func record(_ operation: String, detail: String? = nil, publish: Bool = true) {
        operations[operation, default: 0] += 1
        if let detail { events.append("\(operation): \(detail)") }
        if publish { revision += 1 }
    }

    func recordLive(_ effect: String) {
        live[effect, default: 0] += 1
        events.append("LIVE boundary reached: \(effect)")
        revision += 1
    }

    var liveReport: String {
        liveNames.map { "LIVE \($0): \(live[$0, default: 0])" }.joined(separator: "\n")
    }

    var report: String {
        ([liveReport, "Fixture operations:"] +
            operations.keys.sorted().map { "\($0): \(operations[$0, default: 0])" } +
            ["Events:"] + events).joined(separator: "\n")
    }

    var liveTotal: Int { live.values.reduce(0, +) }
}

/// All data and edits are process-local. No real store, client, auth, notification, scheduler,
/// WidgetCenter, URL opener, or app updater is constructed by this runtime.
@MainActor
final class FixtureSettingsRuntime: ObservableObject, SettingsRuntime {
    let fixture: SettingsFixtureCase
    let effects = SettingsFixtureEffects()
    @Published private(set) var saveFailureArmed = false
    private(set) var ha: HaStoreSnapshot
    private(set) var cp: SettingsCpState
    private var failedPurposes = Set<SettingsDiscoveryPurpose>()
    private let statesJSON: String

    init(fixture: SettingsFixtureCase) {
        self.fixture = fixture
        let config = Self.initialHa(fixture)
        ha = HaStoreSnapshot(config: config, scope: "settings-fixture-\(fixture.rawValue)")
        cp = SettingsCpState(
            session: fixture == .fresh ? CpSession() :
                CpSession(token: "fixture-cp-cookie", userId: 4242, email: "fixture@example.invalid"),
            location: fixture == .fresh ? nil : CpLocation(
                name: "Fixture chargers", address: "100 Sample Street", deviceIds: [101, 102],
                bounds: cpBounds(lat: 47.6, lon: -122.3), city: "Sample City", state: "WA"),
            auto: fixture != .fresh, alerts: CpAlertPrefs())
        statesJSON = Self.discoveryJSON(includeAlarm: fixture != .haWithoutAlarm)
        let recorder = effects
        SettingsEffectAudit.record = { [weak recorder] effect in recorder?.recordLive(effect) }
        effects.record("fixture", detail: fixture.rawValue, publish: false)
    }

    func loadHa() -> HaStoreSnapshot? {
        effects.record("loadHa", publish: false)
        return ha
    }

    func saveHaEdit(expectedScope: String?, edit: SettingsHaEdit) throws -> HaConfig? {
        if saveFailureArmed {
            saveFailureArmed = false
            effects.record("saveHaEdit.failed", detail: "Injected shared-storage failure; persisted config unchanged")
            throw HaError("Shared storage is unavailable. Please reopen Hearth.")
        }
        switch edit {
        case .fields(let mutate):
            guard expectedScope == ha.scope, var next = ha.config else {
                throw HaError("Your account changed. Reopen Settings to continue.")
            }
            let before = ha.config
            mutate(&next)
            let collectionChanged = haCollectionSelectionChanged(before, next)
            let climateChanged = before?.climateId != next.climateId || before?.resumeId != next.resumeId
            let alarmChanged = before?.entityId != next.entityId || before?.lockId != next.lockId
            ha = HaStoreSnapshot(config: next, scope: ha.scope,
                climateRevision: climateChanged ? UUID().uuidString : ha.climateRevision,
                alarmRevision: alarmChanged ? UUID().uuidString : ha.alarmRevision,
                collectionRevision: collectionChanged ? UUID().uuidString : ha.collectionRevision,
                doorActionRevision: collectionChanged ? UUID().uuidString : ha.doorActionRevision)
            effects.record("saveHaEdit", detail: persistedHaReport)
            return next
        case .signOut:
            ha = HaStoreSnapshot(config: nil, scope: "settings-fixture-signed-out-\(UUID().uuidString)")
            effects.record("saveHaEdit.signOut", detail: "HA cleared; CP signed in: \(cp.session.isSignedIn)")
            return nil
        }
    }

    func discoverHa(config: HaConfig, scope: String?,
                    purpose: SettingsDiscoveryPurpose) async throws -> SettingsDiscovery {
        effects.record("discoverHa", detail: String(describing: purpose))
        let json = try await settingsDiscoveryJson(config: config, scope: scope,
            current: { self.loadHa() }, read: { _ in
                await Task.yield()
                try Task.checkCancellation()
                if self.fixture == .haExpired {
                    self.effects.record("discoverHa.failed", detail: "HA 401; CP unchanged")
                    throw HaError("Signed out: sign in again", code: 401)
                }
                // Each production consumer can show a first failure and a successful retry.
                // A background names read therefore cannot consume the picker's failure.
                if self.fixture == .discoveryFailed, self.failedPurposes.insert(purpose).inserted {
                    self.effects.record("discoverHa.failed", detail: "Canned offline response")
                    throw URLError(.notConnectedToInternet)
                }
                return self.statesJSON
            })
        effects.record("discoverHa.succeeded", detail: String(describing: purpose))
        return SettingsDiscovery(statesJSON: json, homeName: "Fixture home")
    }

    func loadCp() -> SettingsCpState {
        effects.record("loadCp", publish: false)
        return cp
    }

    func performCpEdit(_ edit: SettingsCpEdit, expected: CpSettingsOrigin?) async throws -> SettingsCpState {
        try Task.checkCancellation()
        let detail: String
        switch edit {
        case .location(let location):
            cp.location = location
            detail = "location: \(location?.title ?? "None")"
            refreshWidgets(kinds: [])
        case .locationName(let name):
            if let location = cp.location {
                cp.location = CpLocation(name: location.name, address: location.address,
                    deviceIds: location.deviceIds, bounds: location.bounds, city: location.city,
                    state: location.state, label: name)
            }
            detail = "location name: \(name)"
        case .signOut:
            cp.session = CpSession()
            cp.location = nil
            cp.auto = false
            detail = "CP cleared; HA present: \(ha.config != nil)"
            refreshWidgets(kinds: [])
        case .auto(let desired, _):
            cp.auto = desired != .pause && cp.session.isSignedIn && cp.location != nil
            detail = "Auto: \(cp.auto)"
            effects.record("would.refreshCp")
            if cp.auto { effects.record("would.requestNotificationPermission") }
        case .alert(let key, let on):
            switch key {
            case "offer": cp.alerts.offer = on
            case "accepted": cp.alerts.accepted = on
            case "snoozed": cp.alerts.snoozed = on
            case "second": cp.alerts.second = on
            default: throw HaError("Unknown ChargePoint alert")
            }
            detail = "alert \(key): \(on)"
        }
        effects.record("performCpEdit", detail: detail)
        return cp
    }

    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination {
        effects.record("openSetupRoute", detail: route.rawValue)
        return .fixture
    }

    func refreshWidgets(kinds: Set<String>) {
        effects.record("refreshWidgets", detail: kinds.isEmpty ? "all (recorded only)" : kinds.sorted().joined(separator: ","))
    }

    func failNextSave() {
        saveFailureArmed = true
        effects.record("armSaveFailure")
    }

    var persistedHaReport: String {
        guard let config = ha.config else { return "HA: nil" }
        return [
            "HA alarm: \(config.entityId.isEmpty ? "None" : config.entityId)",
            "HA scripts (\(config.scriptIds.count)): \(config.scriptIdsJson)",
            "HA favourites (\(config.favouriteIds.count)): \(config.favouriteIdsJson)",
            "HA doors (\(config.doorIds.count)): \(config.doorIdsJson)",
            "HA doorsChosen: \(config.doorsChosen)",
            "HA sensors: \(config.sensorsJson)",
            "HA light pins: \(config.lightPinsJson)"
        ].joined(separator: "\n")
    }

    var persistedReport: String {
        [
            "Case: \(fixture.rawValue)", "Scope: \(ha.scope)", persistedHaReport,
            "CP signed in: \(cp.session.isSignedIn)", "CP location: \(cp.location?.title ?? "None")",
            "CP Auto: \(cp.auto)",
            "CP alerts: offer=\(cp.alerts.offer), accepted=\(cp.alerts.accepted), snoozed=\(cp.alerts.snoozed), second=\(cp.alerts.second)"
        ].joined(separator: "\n")
    }

    private static func initialHa(_ fixture: SettingsFixtureCase) -> HaConfig? {
        guard fixture != .fresh, fixture != .chargepointOnly else { return nil }
        var config = HaConfig(baseUrl: "https://settings-fixture.invalid", token: "fixture-ha-token",
            entityId: fixture == .haWithoutAlarm ? "" : "alarm_control_panel.home",
            lockId: "lock.front", lockName: "Front door", climateId: "climate.home",
            resumeId: "button.resume", sensorsJson: #"["sensor.room_temperature"]"#,
            doorIdsJson: #"["cover.garage","lock.front"]"#, scriptIdsJson: #"["script.fixture_1"]"#,
            lightPinsJson: #"["light.kitchen"]"#, favouriteIdsJson: #"["switch.fixture_1"]"#, doorsChosen: true)
        switch fixture {
        case .haExpired:
            config.token = ""
            config.refreshToken = "fixture-expired-refresh"
        case .pickerMissing:
            config.scriptIdsJson = #"["script.missing","script.fixture_1"]"#
            config.favouriteIdsJson = #"["switch.missing","switch.fixture_1"]"#
            config.doorIdsJson = #"["cover.missing","cover.garage"]"#
            config.sensorsJson = #"["sensor.missing","sensor.room_temperature"]"#
        case .pickerOverLimit:
            config.scriptIdsJson = encode((1...8).map { "script.fixture_\($0)" })
            config.favouriteIdsJson = encode((1...14).map { "switch.fixture_\($0)" })
        default: break
        }
        return config
    }

    private static func encode(_ ids: [String]) -> String {
        String(data: try! JSONEncoder().encode(ids), encoding: .utf8)!
    }

    private static func discoveryJSON(includeAlarm: Bool) -> String {
        var rows: [[String: Any]] = []
        func add(_ id: String, _ name: String, deviceClass: String? = nil) {
            var attributes: [String: Any] = ["friendly_name": name]
            if let deviceClass { attributes["device_class"] = deviceClass }
            rows.append(["entity_id": id, "state": "off", "attributes": attributes])
        }
        if includeAlarm { add("alarm_control_panel.home", "Home alarm") }
        add("lock.front", "Front door")
        add("climate.home", "Home thermostat")
        add("button.resume", "Resume comfort")
        add("sensor.room_temperature", "Room temperature", deviceClass: "temperature")
        add("binary_sensor.front_door", "Front door sensor", deviceClass: "door")
        add("cover.garage", "Garage", deviceClass: "garage")
        add("light.kitchen", "Kitchen")
        for i in 1...10 { add("script.fixture_\(i)", String(format: "Script %02d", i)) }
        for i in 1...14 { add("switch.fixture_\(i)", String(format: "Switch %02d", i)) }
        return String(data: try! JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!
    }
}

/// The actual production Settings Form, sections, navigation links and pickers are under test.
@MainActor
struct SettingsFixtureScreen: View {
    @StateObject private var runtime: FixtureSettingsRuntime

    init(fixture: SettingsFixtureCase) {
        _runtime = StateObject(wrappedValue: FixtureSettingsRuntime(fixture: fixture))
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsView(config: runtime.loadHa()?.config, runtime: runtime, onChange: { _ in })
            SettingsFixtureEffectsPanel(runtime: runtime)
        }
    }
}

@MainActor
private struct SettingsFixtureEffectsPanel: View {
    let runtime: FixtureSettingsRuntime
    @ObservedObject private var effects: SettingsFixtureEffects
    @State private var showingLedger = false

    init(runtime: FixtureSettingsRuntime) {
        self.runtime = runtime
        _effects = ObservedObject(wrappedValue: runtime.effects)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Fixture · \(runtime.fixture.rawValue)").font(.caption)
                Spacer()
                Button("Fail next save") { runtime.failNextSave() }
                    .accessibilityIdentifier("settings.fixture.failSave")
                Button("Ledger") { showingLedger = true }
                    .accessibilityIdentifier("settings.fixture.showLedger")
            }
            Text("LIVE effects: \(effects.liveTotal) · Transport/store/scheduler/notifications/timelines/URL/auth/updater")
                .font(.caption2)
                .accessibilityIdentifier("settings.fixture.effects")
                .accessibilityValue(effects.report + "\n" + runtime.persistedReport)
        }
        .padding(8)
        .background(.bar)
        .sheet(isPresented: $showingLedger) {
            NavigationStack {
                ScrollView {
                    Text(effects.report + "\n\n" + runtime.persistedReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .accessibilityIdentifier("settings.fixture.ledger")
                }
                .navigationTitle("Fixture ledger")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingLedger = false }
                    }
                }
            }
        }
    }
}
#endif
