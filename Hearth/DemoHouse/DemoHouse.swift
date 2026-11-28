#if DEBUG
import Foundation
import HearthKit

/// DEBUG-only "demo house" mode for the render harness (docs/RENDER-HARNESS.md). With `-demoHouse`,
/// the app behaves as fully signed in to one fictional Home Assistant + ChargePoint account with
/// healthy, populated data and every feature enabled, so the REAL screens (HomeView and every
/// sheet/page) render as if lived in, with no real backend. Entirely inert without the launch
/// argument, simulator only (it overwrites the stored accounts), and not compiled into Release.
///
/// How it works:
///  - Registers `DemoHouseURLProtocol` on `URLSession.shared` to answer all Home Assistant REST calls
///    (states, single-entity state, template, service calls, logbook) with canned data for the house.
///  - Writes a complete signed-in `HaConfig` to the App Group store so the root becomes the real
///    `HomeView` and Home lists every widget as added.
///  - Seeds local feature state (Goodnight, Routines + learned history, Morning commute, Leave-by,
///    Travel days, Safety alerts) and puts Card style and the widget names back to their defaults.
///  - Seeds the ChargePoint store + a canned transport (see DemoHouseChargePoint) so ChargePoint reads
///    connected and populated.
///  - The next launch without `-demoHouse` signs the fictional accounts out again.
enum DemoHouse {
    static let argument = "-demoHouse"

    /// The demo house replaces the stored Home Assistant and ChargePoint accounts, so it only ever
    /// runs in the simulator: never on a phone, even in a DEBUG build.
    #if targetEnvironment(simulator)
    private static let supported = true
    #else
    private static let supported = false
    #endif

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isActive: Bool { supported && arguments.contains(argument) }

    /// Call once from `HearthApp.init`, before `ContentView` reads the config.
    static func prepareLaunch() {
        guard supported else { return }
        if isActive {
            activate()
        } else if CpSessionStore.demoAccountsStored || arguments.contains("-renderSignedOut") {
            // A launch without `-demoHouse` never goes on using the fictional accounts (its requests
            // would leave for real servers), and `-renderSignedOut` is the fresh sign-in screen.
            signOut()
        }
    }

    private static func activate() {
        URLProtocol.registerClass(DemoHouseURLProtocol.self)
        CpSessionStore.demoAccountsStored = true
        seedHomeAssistant(sessionExpired: arguments.contains("-demoSessionExpired"))
        DemoHouseThermostat.seedReadings()
        seedFeatures()
        seedLook()
        DemoHouseChargePoint.seed()
    }

    /// Back to a fresh install's accounts: no Home Assistant config, ChargePoint signed out.
    private static func signOut() {
        do { try HaConfigStore.clear() }
        catch { NSLog("[DemoHouse] clearing the stored HaConfig failed: \(error)") }
        do { try CpSessionStore.recoverSignedOut() }
        catch { NSLog("[DemoHouse] signing ChargePoint out failed: \(error)") }
        CpSessionStore.demoAccountsStored = false
    }

    /// `-demoPickerSearch <text>`: the entity pickers open with this search already typed.
    static var pickerSearchSeed: String {
        guard isActive else { return "" }
        return value(after: "-demoPickerSearch") ?? ""
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    // MARK: - Home Assistant config

    /// The signed-in demo account. With `-demoSessionExpired` the refresh token is dropped, so
    /// `isSignedIn` is false while `carReady` stays true (token present): Home then renders with its
    /// sign-in banner and paused widgets.
    private static func seedHomeAssistant(sessionExpired: Bool) {
        var config = DemoHouseCatalog.config
        if sessionExpired { config.refreshToken = "" }
        do { try HaConfigStore.clear() }
        catch { NSLog("[DemoHouse] clearing the stored HaConfig failed: \(error)") }
        do { try HaConfigStore.save(config) }
        catch { NSLog("[DemoHouse] HaConfig seed failed: \(error)") }
    }

    // MARK: - Look

    /// Every launch starts from the same look, whatever an earlier walk tapped: Card style is the
    /// default (or `-demoCardStyle <value>`, in `parityCardStyle` syntax, e.g. `colour:plum`), no
    /// widget has its own style and none is renamed.
    private static func seedLook() {
        let style = value(after: "-demoCardStyle").flatMap(parityCardStyle) ?? .default
        do {
            try CardStyleStore.save(style, to: .allCards)
            for kind in HomeWidgetKind.allCases {
                try CardStyleStore.clearOverride(for: kind)
                WidgetNameStore.setName(nil, for: kind)
            }
        } catch { NSLog("[DemoHouse] Card style seed failed: \(error)") }
    }

    // MARK: - Local feature state

    private static func seedFeatures() {
        // Goodnight: enabled with hours, arm mode and a keep-on light.
        GoodnightStore.save(GoodnightConfig(enabled: true, startHour: 22, endHour: 6,
                                            armMode: .night, keepOnLights: ["light.bedroom"]))

        // Routines: on, with enough history for one learned evening routine.
        HouseFeaturesStore.routinesEnabled = true
        ActionHistoryStore.save(learnedRoutineHistory())

        // Morning commute: both toggles on, recent sensor activity for the detection row.
        CommuteStore.enabled = true
        CommuteStore.checkBeforeLeaveEnabled = true
        CommuteStore.lastHeard = Date()

        // Leave-by, Travel days, Safety alerts: all on.
        HouseFeaturesStore.leaveByEnabled = true
        HouseFeaturesStore.leaveByMinutes = 20
        HouseFeaturesStore.travelEnabled = true
        HouseFeaturesStore.safetyEnabled = true
    }

    /// Five consecutive recent days at ~22:30 with the same action set + source key: ≥4 distinct days
    /// clustered within ±45 min, which `RoutinesSuggester` surfaces as a learned routine.
    private static func learnedRoutineHistory() -> [ActionHistoryRecord] {
        let calendar = Calendar.current
        let entities = ["light.living_room", "light.kitchen", "lock.front_door"]
        return (0..<5).compactMap { day in
            guard let base = calendar.date(byAdding: .day, value: -day, to: Date()),
                  let timestamp = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: base) else { return nil }
            return ActionHistoryRecord(timestamp: timestamp, entityIDs: entities, sourceKey: "evening")
        }
    }
}
#endif
