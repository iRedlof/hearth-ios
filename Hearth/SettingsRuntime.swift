import SwiftUI
import WidgetKit
import HearthKit

/// Settings consumes the existing provider models; the runtime owns persistence and effects.
struct SettingsDiscovery {
    let statesJSON: String
    let entities: [HaEntity]
    let homeName: String?

    init(statesJSON: String, homeName: String? = nil) {
        self.statesJSON = statesJSON
        entities = parseEntities(statesJSON)
        self.homeName = homeName
    }
}

enum SettingsDiscoveryPurpose: Hashable {
    case names
    case entity(String)
    case entities([String], doorsOnly: Bool)
}

struct SettingsCpState {
    var session: CpSession
    var location: CpLocation?
    var auto: Bool
    var alerts: CpAlertPrefs

    var accountName: String {
        let local = session.email.split(separator: "@").first.map(String.init) ?? ""
        return local.isEmpty ? "Signed in" : local
    }
}

enum SettingsCpEdit {
    case location(CpLocation?)
    case locationName(String)
    case signOut
    case auto(Bool)
    case alert(String, Bool)
}

enum SettingsHaEdit {
    case fields((inout HaConfig) -> Void)
    case signOut
}

enum SettingsSetupRoute: String {
    case haSignIn, cpSignIn, cpLocation

    var title: String {
        switch self {
        case .haSignIn: "Connect Home Assistant"
        case .cpSignIn: "Sign in to ChargePoint"
        case .cpLocation: "ChargePoint location"
        }
    }
}

enum SettingsSetupDestination {
    case live, fixture
}

@MainActor
protocol SettingsRuntime: AnyObject {
    func loadHa() -> HaStoreSnapshot?
    func saveHaEdit(expectedScope: String?, edit: SettingsHaEdit) throws -> HaConfig?
    func discoverHa(config: HaConfig, scope: String?,
                    purpose: SettingsDiscoveryPurpose) async throws -> SettingsDiscovery
    func loadCp() -> SettingsCpState
    func performCpEdit(_ edit: SettingsCpEdit) async throws -> SettingsCpState
    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination
    func refreshWidgets(kinds: Set<String>)
}

/// A fixture installs a recorder here before its Settings tree exists. Live adapter entry points
/// record before touching real dependencies, so an accidental live default is visible in the ledger.
/// This boundary audit complements the root's source and actual App Group file checks.
@MainActor
enum SettingsEffectAudit {
    static var record: ((String) -> Void)?
    static func reached(_ effect: String) { record?(effect) }
}

@MainActor
final class LiveSettingsRuntime: SettingsRuntime {
    static let shared = LiveSettingsRuntime()
    private init() {}

    func loadHa() -> HaStoreSnapshot? {
        SettingsEffectAudit.reached("storeReads")
        return HaConfigStore.context()
    }

    func saveHaEdit(expectedScope: String?, edit: SettingsHaEdit) throws -> HaConfig? {
        switch edit {
        case .fields(let mutate):
            guard let expectedScope else {
                throw HaError("Your account changed. Reopen Settings to continue.")
            }
            SettingsEffectAudit.reached("storeWrites")
            return try HaConfigStore.editConfig(expectedScope: expectedScope, mutate: mutate)
        case .signOut:
            SettingsEffectAudit.reached("storeWrites")
            try HaConfigStore.clear()
            SettingsEffectAudit.reached("auth")
            Task { await HaAuth.shared.forget() }
            return nil
        }
    }

    func discoverHa(config: HaConfig, scope: String?,
                    purpose: SettingsDiscoveryPurpose) async throws -> SettingsDiscovery {
        let json = try await settingsDiscoveryJson(config: config, scope: scope,
            current: { self.loadHa() }, read: { latest in
                SettingsEffectAudit.reached("transport")
                return try await HaClient(latest).allStatesJson()
            })
        return SettingsDiscovery(statesJSON: json)
    }

    func loadCp() -> SettingsCpState {
        SettingsEffectAudit.reached("storeReads")
        return SettingsCpState(session: CpSessionStore.load(), location: CpSessionStore.loadLocation(),
                               auto: CpSessionStore.loadRun().armed, alerts: CpSessionStore.loadAlertPrefs())
    }

    func performCpEdit(_ edit: SettingsCpEdit) async throws -> SettingsCpState {
        SettingsEffectAudit.reached("storeWrites")
        switch edit {
        case .location(let location):
            CpSessionStore.saveLocation(location)
            refreshWidgets(kinds: [])
        case .locationName(let name):
            if let location = CpSessionStore.loadLocation() {
                CpSessionStore.saveLocation(CpLocation(name: location.name, address: location.address,
                    deviceIds: location.deviceIds, bounds: location.bounds, city: location.city,
                    state: location.state, label: name))
            }
        case .signOut:
            CpSessionStore.clear()
            refreshWidgets(kinds: [])
        case .auto(let on):
            if on {
                SettingsEffectAudit.reached("transport")
                await CpWidgetOperation.enableAuto()
            } else {
                CpSessionStore.saveRun(cpPauseRun(CpSessionStore.loadRun()))
            }
            if CpSessionStore.loadRun().armed {
                SettingsEffectAudit.reached("notifications")
                CpNotify.requestPermission()
            }
            // Retain the existing app RefreshSignal and CP timeline behavior.
            SettingsEffectAudit.reached("timelines")
            SettingsEffectAudit.reached("appUpdater")
            CpWidgetOperation.reload()
        case .alert(let key, let on):
            CpSessionStore.setAlert(key, on)
        }
        return loadCp()
    }

    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination {
        // Record before a live sign-in/search view is constructed (it owns its existing effects).
        SettingsEffectAudit.reached("URL")
        SettingsEffectAudit.reached(route == .cpLocation ? "transport" : "auth")
        return .live
    }

    func refreshWidgets(kinds: Set<String>) {
        SettingsEffectAudit.reached("timelines")
        if kinds.isEmpty { WidgetCenter.shared.reloadAllTimelines() }
        else { for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) } }
    }
}

/// Production routes use their existing screens. An injected fixture decides its destination before
/// any live sign-in/search view can initialize or begin a task.
@MainActor
struct SettingsSetupScreen: View {
    let route: SettingsSetupRoute
    let runtime: any SettingsRuntime
    var initialURL: String? = nil
    let onComplete: () -> Void
    @State private var destination: SettingsSetupDestination?

    init(route: SettingsSetupRoute, runtime: any SettingsRuntime, initialURL: String? = nil,
         onComplete: @escaping () -> Void) {
        self.route = route; self.runtime = runtime; self.initialURL = initialURL
        self.onComplete = onComplete
        _destination = State(initialValue: nil)
    }

    var body: some View {
        Group {
            switch destination {
            case .live:
                switch route {
                case .haSignIn: SignInView(initialURL: initialURL, onSignedIn: onComplete)
                case .cpSignIn: CpSignInView(onSignedIn: onComplete)
                case .cpLocation: CpLocationSearchView(onPicked: onComplete)
                }
            case .fixture:
                List {
                    Text(route.title)
                    Text("Setup route recorded.")
                        .foregroundStyle(.secondary)
                }
                .navigationTitle(route.title)
                .accessibilityIdentifier("settings.fixture.destination.\(route.rawValue)")
            case nil:
                ProgressView()
            }
        }
        .onAppear {
            if case nil = destination { destination = runtime.openSetupRoute(route) }
        }
    }
}
