import SwiftUI
import WidgetKit
import HearthKit

#if DEBUG
struct ParityWidgetSelection: Sendable {
    let id: String
    let run: String
}
#endif

/// The core-state catalog for the iOS↔Android parity gallery (docs/parity-comparison).
/// Each entry mirrors the Android BeaconFixtures scenario of the same id, so the two
/// platforms can be compared side by side. Rendered by *displaying* `ParityStateScreen`
/// (launched with `-parityState <id>`) and screenshotting — the Beacon views use
/// WidgetKit-only modifiers that don't realise under ImageRenderer/XCTest.
@MainActor enum ParityCatalog {
    #if DEBUG
    nonisolated private static var fixtureStore: UserDefaults {
        UserDefaults(suiteName: HaConfigStore.appGroup) ?? .standard
    }
    /// Dedicated simulator captures only. Fixture mode bypasses provider reads and real actions.
    nonisolated static func widgetSelection(prefix: String) -> ParityWidgetSelection? {
        guard let selection = fixtureStore.dictionary(forKey: "parityWidgetSelection"),
              let id = selection["id"] as? String, let run = selection["run"] as? String,
              id.hasPrefix(prefix + "-") else { return nil }
        return ParityWidgetSelection(id: id, run: run)
    }
    nonisolated static func activeWidgetID(prefix: String) -> String? {
        widgetSelection(prefix: prefix)?.id
    }
    static func activateWidget(_ id: String) {
        guard view(id) != nil, let prefix = id.split(separator: "-").first else { return }
        fixtureStore.removeObject(forKey: "parityWidgetRendered")
        let arguments = ProcessInfo.processInfo.arguments
        let run: String
        if let index = arguments.firstIndex(of: "-parityRun"), index + 1 < arguments.count {
            run = arguments[index + 1]
        } else {
            run = ""
        }
        fixtureStore.set(["id": id, "run": run], forKey: "parityWidgetSelection")
        fixtureStore.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.\(prefix)")
    }
    static func deactivateWidget() {
        fixtureStore.removeObject(forKey: "parityWidgetState")
        fixtureStore.removeObject(forKey: "parityWidgetRendered")
        fixtureStore.removeObject(forKey: "parityWidgetRun")
        fixtureStore.removeObject(forKey: "parityWidgetSelection")
        fixtureStore.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func recordWidgetFrame(_ selection: ParityWidgetSelection, size: CGSize, dynamicType: DynamicTypeSize,
                                  sizeCategory: ContentSizeCategory, family: WidgetFamily, bodyPoints: CGFloat) {
        fixtureStore.set(["id": selection.id, "width": size.width, "height": size.height,
                          "dynamicTypeSize": String(describing: dynamicType),
                          "sizeCategory": String(describing: sizeCategory),
                          "widgetFamily": String(describing: family),
                          "scaledBodyPoints": bodyPoints,
                          "run": selection.run,
                          "bundleID": Bundle.main.bundleIdentifier ?? "",
                          "processID": ProcessInfo.processInfo.processIdentifier,
                          "timestamp": Date().timeIntervalSince1970], forKey: "parityWidgetRendered")
        fixtureStore.synchronize()
    }
    static func recordReadableTextFrame(_ id: String, size: CGSize) {
        guard let selection = widgetSelection(prefix: "readable"), selection.id == id else { return }
        fixtureStore.set(["id": id, "run": selection.run, "width": size.width, "height": size.height,
                          "processID": ProcessInfo.processInfo.processIdentifier,
                          "timestamp": Date().timeIntervalSince1970], forKey: "parityReadableTextFrame")
        fixtureStore.synchronize()
    }
    #endif
    static func view(_ id: String) -> AnyView? {
        all().first { $0.0 == id }?.1
    }

    static func all() -> [(String, AnyView)] {
        #if DEBUG
        let small = SmallWidgetConceptCatalog.concepts.map { ($0.id, AnyView(SmallWidgetConceptView(concept: $0))) }
        let readable = AccessibleBeaconConceptCatalog.concepts.map {
            ($0.id, AnyView(AccessibleBeaconConceptView(concept: $0)))
        }
        let nativeReadable = AccessibleBeaconConceptCatalog.concepts.map {
            ($0.nativeID, AnyView(AccessibleBeaconConceptView(concept: $0)))
        }
        return alarm() + thermostat() + car() + chargePoint() + tiles() + collections() + small + readable + nativeReadable
        #else
        alarm() + thermostat() + car() + chargePoint() + tiles() + collections()
        #endif
    }

    private static func tiles() -> [(String, AnyView)] {
        TileParityInputs.states.flatMap { state in [
            ("favourites-" + state, AnyView(FavouritesView(TileParityInputs.favourites(state)))),
            ("lights-" + state, AnyView(LightTileView(TileParityInputs.lights(state)))),
            ("quick-" + state, AnyView(QuickView(TileParityInputs.quick(state))))
        ] }
    }
    private static func collections() -> [(String, AnyView)] {
        CollectionParityInputs.doorsStates.map {
            ("doors-" + $0, AnyView(DoorsView(CollectionParityInputs.doors($0))))
        } + CollectionParityInputs.activityStates.map {
            ("activity-" + $0, AnyView(ActivityView(CollectionParityInputs.activity($0), now: CollectionParityInputs.now)))
        } + CollectionParityInputs.batteryStates.map {
            ("battery-" + $0, AnyView(BatteryView(CollectionParityInputs.batteries($0))))
        }
    }
    // MARK: Alarm
    private static func alarm() -> [(String, AnyView)] {
        AlarmParityInputs.states.map { ("alarm-" + $0, AnyView(AlarmBeaconView(AlarmParityInputs.snapshot($0)))) }
    }

    // MARK: Thermostat
    private static func thermostat() -> [(String, AnyView)] {
        ThermostatParityInputs.states.map {
            ("thermostat-" + $0, AnyView(ThermostatBeaconView(ThermostatParityInputs.snapshot($0))))
        }
    }

    // MARK: Car
    private static func car() -> [(String, AnyView)] {
        CarParityInputs.states.map { ("car-" + $0, AnyView(CarBeaconView(CarParityInputs.snapshot($0)))) }
    }

    // MARK: ChargePoint
    private static func chargePoint() -> [(String, AnyView)] {
        let now = Date()
        let rows: [(String, String?, Int?, Bool)] = [
            ("available", nil, nil, false), ("waiting", "WAITING", nil, false),
            ("offer", "ACCEPT_PENDING", 1, false), ("offer_last", "ACCEPT_PENDING", 0, false),
            ("held", "PENDING_PLUG_IN", 1, false), ("held_unknown", "PENDING_PLUG_IN", nil, false),
            ("auto_held_last", "PENDING_PLUG_IN", 0, true), ("dib_held", "DIB_PENDING_PLUG_IN", 1, false),
            ("offer_no_floor", "ACCEPT_PENDING", 1, false), ("snoozed", "PASS", nil, false),
            ("charging", "CHARGING", nil, false), ("charging_no_stop", "CHARGING", nil, false),
            ("done", "PENDING_PLUG_OUT", nil, false), ("fault", "CHARGING_FAULT", nil, false),
            ("unplugged", "DIB_PLUG_OUT", nil, false), ("overstayed", "OVER_STAYED", nil, false),
            ("blocked", "BLOCKED", nil, false), ("pending", "PENDING", nil, false),
            ("signed_out", nil, nil, false), ("no_location", nil, nil, false), ("cant_join", nil, nil, true),
            ("expired", "ACCEPT_PENDING", 1, false), ("unknown_deadline", "ACCEPT_PENDING", 1, true),
            ("working_accept", "ACCEPT_PENDING", 1, true), ("failed_accept", "ACCEPT_PENDING", 1, true),
            ("auto_waiting", "WAITING", nil, true), ("auto_snoozed", "PASS", nil, true)
        ]
        return rows.map { id, status, allowance, auto in
            let location = ["signed_out", "no_location"].contains(id) ? nil :
                CpLocation(name: "Amazon Day 1", address: "", deviceIds: Array(1...43).map(Int64.init),
                           bounds: cpBounds(lat: 0, lon: 0))
            let deadline = id == "unknown_deadline" ? 0 : Int64(now.addingTimeInterval(id == "expired" ? -1 : 1690).timeIntervalSince1970 * 1000)
            let offer = CpOffer(deviceId: 1, port: 1,
                charger: id == "offer_no_floor" ? "SEA41-29" : "SEA41 - 29 P3",
                untilMs: deadline, startMs: Int64(now.addingTimeInterval(600).timeIntervalSince1970 * 1000))
            let charging = status == "CHARGING" ? CpCharging(sessionId: 9, powerKw: 6.6, energyKwh: 7.4,
                minutes: 65, canStop: id != "charging_no_stop", miles: 31, vehicle: "Tesla Model Y", charger: "SEA41 - 29 P3") : nil
            let floors = zip(["P2", "P3", "P4", "P5", "P6"], [14, 18, 22, 22, 10]).enumerated().map { index, pair in
                CpFloor(level: pair.0, free: status == nil ? [8, 17, 22, 21, 10][index] : 0, total: pair.1)
            }
            let state = CpState(signedOut: id == "signed_out",
                account: cpAccount(hasSession: id != "signed_out", expired: false, joinExpired: id == "cant_join"),
                location: location, now: location == nil ? nil : CpNow(free: 78, inUse: 7, offline: 1, stations: 43),
                waitlist: status.map { .inLine(place: $0 == "WAITING" ? 3 : nil, state: $0, stations: 43, offer: offer, auto: false) } ?? .notQueued,
                charging: charging, autoOn: auto, floors: floors, snoozesLeft: allowance)
            let snapshot = cpSnapshot(state, email: "iredlof@example.com",
                                      checkedAt: now.formatted(date: .omitted, time: .shortened), now: now)
            let operation = id == "working_accept" ? CpOperation(command: "accept", startedAt: now)
                : id == "failed_accept" ? CpOperation(command: "accept", startedAt: now, error: "Offer expired") : nil
            return ("chargepoint-\(id)", AnyView(CpBeaconView(cpApplyingOperation(snapshot, operation, now: now))))
        }
    }
}

/// In debug capture mode WidgetKit itself supplies the rounded container and native size.
/// Release builds contain only the normal production view.
struct ParityWidgetContent<Content: View>: View {
    let prefix: String
    @ViewBuilder let content: () -> Content
    #if DEBUG
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.widgetFamily) private var family
    @ScaledMetric(relativeTo: .body) private var bodyPoints: CGFloat = 17
    #endif
    var body: some View {
        #if DEBUG
        if let selection = ParityCatalog.widgetSelection(prefix: prefix),
           let fixture = ParityCatalog.view(selection.id) {
            GeometryReader { geometry in
                let _ = ParityCatalog.recordWidgetFrame(selection, size: geometry.size, dynamicType: dynamicType,
                    sizeCategory: sizeCategory, family: family, bodyPoints: bodyPoints)
                fixture.allowsHitTesting(false).accessibilityIdentifier("parity-\(selection.id)")
            }
        } else { content() }
        #else
        content()
        #endif
    }
}

/// Full-screen single-state card for screenshotting (`-parityState <id>`). The card sits at a fixed
/// top-leading offset on black so the capture script can crop it deterministically.
struct ParityStateScreen: View {
    let id: String
    private var width: CGFloat { dimension("-parityWidth", fallback: 374) }
    private var height: CGFloat { dimension("-parityHeight", fallback: 174) }
    private func dimension(_ flag: String, fallback: CGFloat) -> CGFloat {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count,
              let value = Double(args[index + 1]), value >= 110, value <= 900 else { return fallback }
        return CGFloat(value)
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 1, green: 0, blue: 1).ignoresSafeArea()   // magenta crop marker — appears nowhere in the card
            (ParityCatalog.view(id) ?? AnyView(Text(id).foregroundStyle(.white)))
                .frame(width: width, height: height)
                .allowsHitTesting(false)
                .clipped()
                .padding(.leading, 16).padding(.top, 70)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-parityWidgetKit") {
                ParityCatalog.activateWidget(id)
            }
            #endif
        }
    }
}
