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
    var origin: CpSettingsOrigin? = nil
    var renderedOrigin: CpRenderedOrigin? = nil
    var autoControl: CpAutoControl = .disabled
    var unavailable = false

    var accountName: String {
        let local = session.email.split(separator: "@").first.map(String.init) ?? ""
        return local.isEmpty ? "Signed in" : local
    }
}

enum SettingsCpEdit {
    case location(CpLocation?)
    case locationName(String)
    case signOut
    case auto(CpDesiredAutoAction, CpRenderedOrigin?)
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
    func performCpEdit(_ edit: SettingsCpEdit, expected: CpSettingsOrigin?) async throws -> SettingsCpState
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
        do {
            let current = try CpSessionStore.context()
            return try cpState(current)
        } catch {
            return SettingsCpState(session: CpSession(), location: nil, auto: false, alerts: CpAlertPrefs(), unavailable: true)
        }
    }

    private func cpState(_ current: CpStoreSnapshot) throws -> SettingsCpState {
        SettingsCpState(session: current.session, location: current.location, auto: current.run.armed,
            alerts: current.alerts, origin: current.settingsOrigin, renderedOrigin: current.renderedOrigin,
            autoControl: try current.displaySnapshot().autoControl)
    }

    func performCpEdit(_ edit: SettingsCpEdit, expected: CpSettingsOrigin?) async throws -> SettingsCpState {
        guard let expected else { throw HaError("ChargePoint storage is unavailable. Reopen Settings.") }
        SettingsEffectAudit.reached("storeWrites")
        let repository = try CpSessionStore.repository()
        var localEdit: CpStoreEdit?
        var accepted: CpStoreSnapshot?
        switch edit {
        case .location(let location):
            localEdit = .location(location)
        case .locationName(let name):
            localEdit = .locationName(name)
        case .signOut:
            localEdit = .signOut
        case .auto(let desired, let origin):
            guard let origin, origin.context == expected.context else { throw CpFeedback.detailsChanged }
            SettingsEffectAudit.reached(desired == .pause ? "storeWrites" : "transport")
            let result = try await CpSessionStore.runtime().setAuto(origin: origin, desired: desired)
            let current = try repository.store.snapshot()
            guard current.context.accountGeneration == expected.context.accountGeneration,
                  current.context.selectionRevision == expected.context.selectionRevision,
                  current.context.runID == expected.context.runID else { throw CpFeedback.detailsChanged }
            accepted = current
            if let mode = result.activatedMode {
                _ = try repository.store.withChosenMode(expected: mode) {
                    SettingsEffectAudit.reached("notifications")
                    CpSessionStore.requestOwnedNotificationPermission()
                }
            }
            // Retain the existing app RefreshSignal and CP timeline behavior.
            SettingsEffectAudit.reached("timelines")
            SettingsEffectAudit.reached("appUpdater")
            CpWidgetOperation.reload()
        case .alert(let key, let on):
            guard let preference = CpAlertPreference(rawValue: key) else { throw HaError("Unknown ChargePoint alert") }
            localEdit = .alert(preference, on)
        }
        if let localEdit {
            guard let value = try repository.store.edit(expected: expected, edit: localEdit) else { throw CpFeedback.detailsChanged }
            accepted = value
            if !CpSessionStore.fixtureReloadHandled() { refreshWidgets(kinds: ["com.rohit.hearth.chargepoint"]) }
        }
        guard let accepted else { throw CpFeedback.detailsChanged }
        return try cpState(accepted)
    }

    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination {
#if DEBUG
        // The private ChargePoint host must never construct a live WebKit or MapKit route.
        // Keep Home Assistant navigation independent of this ChargePoint-only override.
        if CpSessionStore.fixtureActive, route == .cpSignIn || route == .cpLocation {
            return .fixture
        }
#endif
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
    let cpOrigin: CpSettingsOrigin?
    let onComplete: () -> Void
    @State private var destination: SettingsSetupDestination?

    init(route: SettingsSetupRoute, runtime: any SettingsRuntime, initialURL: String? = nil, cpOrigin: CpSettingsOrigin? = nil,
         onComplete: @escaping () -> Void) {
        self.route = route; self.runtime = runtime; self.initialURL = initialURL
        self.cpOrigin = cpOrigin ?? (route == .haSignIn ? nil : runtime.loadCp().origin)
        self.onComplete = onComplete
        _destination = State(initialValue: nil)
    }

    var body: some View {
        Group {
            switch destination {
            case .live:
                switch route {
                case .haSignIn: SignInView(initialURL: initialURL, onSignedIn: onComplete)
                case .cpSignIn: CpSignInView(expected: cpOrigin, onSignedIn: onComplete)
                case .cpLocation: CpLocationSearchView(expected: cpOrigin, onPicked: onComplete)
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
