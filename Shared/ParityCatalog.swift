import SwiftUI
import WidgetKit
import HearthKit

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
    nonisolated static func activeWidgetID(prefix: String) -> String? {
        guard let id = fixtureStore.string(forKey: "parityWidgetState"),
              id.hasPrefix(prefix + "-") else { return nil }
        return id
    }
    static func activateWidget(_ id: String) {
        guard view(id) != nil, let prefix = id.split(separator: "-").first else { return }
        fixtureStore.removeObject(forKey: "parityWidgetRendered")
        fixtureStore.set(id, forKey: "parityWidgetState")
        fixtureStore.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.\(prefix)")
    }
    static func deactivateWidget() {
        fixtureStore.removeObject(forKey: "parityWidgetState")
        fixtureStore.removeObject(forKey: "parityWidgetRendered")
        fixtureStore.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func recordWidgetFrame(_ id: String, size: CGSize) {
        fixtureStore.set(["id": id, "width": size.width, "height": size.height,
                          "timestamp": Date().timeIntervalSince1970], forKey: "parityWidgetRendered")
        fixtureStore.synchronize()
    }
    #endif
    private static let sensors = [ThermostatSensor(name: "Outside", value: "48°"),
                                  ThermostatSensor(name: "Bedroom", value: "67.5°"),
                                  ThermostatSensor(name: "Thermo", value: "69.5°")]

    static func view(_ id: String) -> AnyView? {
        all().first { $0.0 == id }?.1
    }

    static func all() -> [(String, AnyView)] {
        alarm() + thermostat() + car() + chargePoint()
    }

    // MARK: Alarm
    private static func alarmCard(_ word: String, _ detail: String, _ tone: BeaconTone, _ glyph: AlarmGlyph,
                                  _ actions: [AlarmAction], doorState: String = "Locked",
                                  doorSince: String? = "since 8:36 AM", doorLocked: Bool? = true,
                                  doorName: String = "Front Door") -> AnyView {
        AnyView(AlarmBeaconView(AlarmSnapshot(name: "Home", checkedAt: "9:41 AM", stateWord: word, detail: detail,
            tone: tone, glyph: glyph, doorName: doorName, doorState: doorState, doorSince: doorSince,
            doorLocked: doorLocked, actions: actions)))
    }
    private static func alarm() -> [(String, AnyView)] {
        [("alarm-disarmed", alarmCard("Disarmed", "Disarmed at 9:42 AM", .blue, .off, [.armHome, .armAway])),
         ("alarm-armed_home", alarmCard("Armed home", "Armed at 7:00 AM", .red, .home, [.disarm])),
         ("alarm-armed_away", alarmCard("Armed away", "Armed at 8:15 AM", .red, .lock, [.disarm])),
         ("alarm-armed_night", alarmCard("Armed night", "Armed at 9:42 AM", .red, .home, [.disarm])),
         ("alarm-armed_vacation", alarmCard("Armed vacation", "Armed at 9:42 AM", .red, .lock, [.disarm])),
         ("alarm-armed_custom_bypass", alarmCard("Armed (bypass)", "Armed at 9:42 AM", .red, .home, [.disarm])),
         ("alarm-arming", alarmCard("Arming…", "Exit delay", .red, .lock, [.disarm])),
         ("alarm-triggered", alarmCard("Alarm triggered", "Triggered at 9:40 AM", .triggered, .alert, [.disarm])),
         ("alarm-offline", alarmCard("Armed home", "Can't reach Home Assistant", .offline, .home, [.disarm],
            doorSince: "Last known", doorLocked: nil)),
         ("alarm-setup", alarmCard("Set up", "Set up the alarm in Settings", .offline, .alert, [],
            doorState: "", doorSince: nil, doorLocked: nil, doorName: ""))]
    }

    // MARK: Thermostat
    private static func thermoCard(_ room: String, _ status: String, _ tone: BeaconTone, heat: String?, cool: String?,
                                   mode: String, fan: String? = "Auto", resume: Bool = true,
                                   humidity: String? = "52% humidity", roomSub: String = "In the room") -> AnyView {
        AnyView(ThermostatBeaconView(ThermostatSnapshot(name: "Thermostat", checkedAt: "9:41 AM", roomTemp: room,
            roomSub: roomSub, humidity: humidity, status: status, tone: tone, heatSetpoint: heat,
            coolSetpoint: cool, mode: mode, fan: fan, canResume: resume, sensors: sensors)))
    }
    private static func thermostat() -> [(String, AnyView)] {
        [("thermostat-auto", thermoCard("67°", "Holding 64–69°", .violet, heat: "64°", cool: "69°", mode: "Auto")),
         ("thermostat-heating", thermoCard("65°", "Heating to 68°", .yellow, heat: "68°", cool: nil, mode: "Heat")),
         ("thermostat-cooling", thermoCard("74°", "Cooling to 70°", .blue, heat: nil, cool: "70°", mode: "Cool")),
         ("thermostat-heat_idle", thermoCard("67°", "Holding 64°", .yellow, heat: "64°", cool: nil, mode: "Heat")),
         ("thermostat-cool_idle", thermoCard("67°", "Holding 69°", .blue, heat: nil, cool: "69°", mode: "Cool")),
         ("thermostat-fan", thermoCard("67°", "Fan only · set 64–69°", .slate, heat: "64°", cool: "69°", mode: "Fan", fan: "On")),
         ("thermostat-off", thermoCard("67°", "Off", .slate, heat: nil, cool: nil, mode: "Off")),
         ("thermostat-offline", thermoCard("67°", "Can't connect", .offline, heat: "64°", cool: "69°", mode: "Auto", roomSub: "Last known")),
         ("thermostat-setup", thermoCard("—", "Tap to connect", .offline, heat: nil, cool: nil, mode: "", fan: nil, resume: false, humidity: "Humidity —", roomSub: "No reading"))]
    }

    // MARK: Car
    private static func carCard(battery: Int?, range: String, lock: String, lockWarn: Bool, doors: String, doorsWarn: Bool,
                                tires: String, tiresWarn: Bool, place: String, sentry: SentryState, charge: String,
                                tone: BeaconTone, cabin: String = "69°F", outside: String = "55°F") -> AnyView {
        AnyView(CarBeaconView(CarSnapshot(name: "Stargate", checkedAt: "9:41 AM", battery: battery, range: range,
            lock: lock, lockWarn: lockWarn, doors: doors, doorsWarn: doorsWarn, cabin: cabin, outside: outside,
            tires: tires, tiresWarn: tiresWarn, place: place, sentry: sentry, chargeLine: charge, tone: tone)))
    }
    private static func car() -> [(String, AnyView)] {
        [("car-parked", carCard(battery: 79, range: "242 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Home · asleep since Mon 10:33 PM",
            sentry: .off, charge: "Unplugged", tone: .mint)),
         ("car-charging", carCard(battery: 64, range: "196 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Home · Awake", sentry: .off,
            charge: "Full by Wed 12:40 AM", tone: .blue)),
         ("car-complete", carCard(battery: 80, range: "245 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Home · asleep since Mon 10:33 PM",
            sentry: .off, charge: "Charged", tone: .mint)),
         ("car-sentry", carCard(battery: 79, range: "242 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Home · asleep since Mon 10:33 PM",
            sentry: .on, charge: "Unplugged", tone: .mint)),
         ("car-low_battery", carCard(battery: 18, range: "55 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Home · Awake", sentry: .off,
            charge: "Low battery", tone: .yellow)),
         ("car-open", carCard(battery: 79, range: "242 mi range", lock: "Unlocked", lockWarn: true, doors: "Trunk open",
            doorsWarn: true, tires: "38–40 psi", tiresWarn: false, place: "Home · Awake", sentry: .off,
            charge: "Unplugged", tone: .yellow)),
         ("car-tires", carCard(battery: 79, range: "242 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "31–40 psi", tiresWarn: true, place: "Home · asleep since Mon 10:33 PM", sentry: .off,
            charge: "Check tires", tone: .yellow)),
         ("car-unlocked_away", carCard(battery: 79, range: "242 mi range", lock: "Unlocked", lockWarn: true, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Away · Awake", sentry: .off,
            charge: "Unplugged", tone: .red)),
         ("car-offline", carCard(battery: 79, range: "242 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Home · Last known", sentry: .off,
            charge: "Last known", tone: .offline))]
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
    var body: some View {
        #if DEBUG
        if let id = ParityCatalog.activeWidgetID(prefix: prefix),
           let fixture = ParityCatalog.view(id) {
            GeometryReader { geometry in
                let _ = ParityCatalog.recordWidgetFrame(id, size: geometry.size)
                fixture.allowsHitTesting(false).accessibilityIdentifier("parity-\(id)")
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
