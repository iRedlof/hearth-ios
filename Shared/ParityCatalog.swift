import SwiftUI
import HearthKit

/// The core-state catalog for the iOS↔Android parity gallery (docs/parity-comparison).
/// Each entry mirrors the Android BeaconFixtures scenario of the same id, so the two
/// platforms can be compared side by side. Rendered by *displaying* `ParityStateScreen`
/// (launched with `-parityState <id>`) and screenshotting — the Beacon views use
/// WidgetKit-only modifiers that don't realise under ImageRenderer/XCTest.
enum ParityCatalog {
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
                                   humidity: String? = "52% humidity") -> AnyView {
        AnyView(ThermostatBeaconView(ThermostatSnapshot(name: "Thermostat", checkedAt: "9:41 AM", roomTemp: room,
            roomSub: "In the room", humidity: humidity, status: status, tone: tone, heatSetpoint: heat,
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
         ("thermostat-offline", thermoCard("67°", "Last known", .offline, heat: "64°", cool: "69°", mode: "Auto")),
         ("thermostat-setup", thermoCard("—", "Unavailable", .offline, heat: nil, cool: nil, mode: "", fan: nil, resume: false, humidity: nil))]
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
         ("car-open", carCard(battery: 79, range: "242 mi range", lock: "Locked", lockWarn: false, doors: "Trunk open",
            doorsWarn: true, tires: "38–40 psi", tiresWarn: false, place: "Home · Awake", sentry: .off,
            charge: "Unplugged", tone: .yellow)),
         ("car-tires", carCard(battery: 79, range: "242 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "31–40 psi", tiresWarn: true, place: "Home · Awake", sentry: .off,
            charge: "Check tires", tone: .yellow)),
         ("car-unlocked_away", carCard(battery: 79, range: "242 mi range", lock: "Unlocked", lockWarn: true, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Away · Awake", sentry: .off,
            charge: "Unplugged", tone: .red)),
         ("car-offline", carCard(battery: 79, range: "242 mi range", lock: "Locked", lockWarn: false, doors: "All shut",
            doorsWarn: false, tires: "38–40 psi", tiresWarn: false, place: "Home · Last known", sentry: .off,
            charge: "Last known", tone: .offline))]
    }

    // MARK: ChargePoint
    private static func cpCard(_ big: String, unit: String = "", sub: String = "", plugsFree: String? = nil,
                               action: String = "Open", keys: [CpKey] = [], deadlineIn: TimeInterval? = nil,
                               goTo: String? = nil, floors: [CpFloor] = [], site: String = "Amazon Day 1",
                               account: String = "iredlof") -> AnyView {
        AnyView(CpBeaconView(CpSnapshot(site: site, account: account, bigAnswer: big, unit: unit, sub: sub,
            plugsFree: plugsFree, autoOn: true, actionLabel: action, keys: keys,
            deadline: deadlineIn.map { Date().addingTimeInterval($0) }, goTo: goTo, floors: floors)))
    }
    private static func chargePoint() -> [(String, AnyView)] {
        let full = [CpFloor(level: "P2", free: 8, total: 14), CpFloor(level: "P3", free: 17, total: 18),
                    CpFloor(level: "P4", free: 22, total: 22), CpFloor(level: "P5", free: 21, total: 22),
                    CpFloor(level: "P6", free: 10, total: 10)]
        let busy = [CpFloor(level: "P2", free: 0, total: 14), CpFloor(level: "P3", free: 0, total: 18),
                    CpFloor(level: "P4", free: 0, total: 22), CpFloor(level: "P5", free: 0, total: 22),
                    CpFloor(level: "P6", free: 0, total: 10)]
        return [("chargepoint-available", cpCard("78", unit: "plugs free", action: "Join", floors: full)),
         ("chargepoint-waiting", cpCard("#3", unit: "in line", sub: "43 chargers",
            keys: [CpKey(command: "leave", label: "Leave")], floors: busy)),
         ("chargepoint-offer", cpCard("Your turn", sub: "Respond by 10:13 AM",
            keys: [CpKey(command: "accept", label: "Accept"), CpKey(command: "snooze", label: "Snooze")],
            deadlineIn: 833, goTo: "SEA41-29 P3")),
         ("chargepoint-held", cpCard("Held", sub: "Plug in by 10:28 AM",
            keys: [CpKey(command: "start", label: "Start"), CpKey(command: "snooze", label: "Snooze")],
            deadlineIn: 1690, goTo: "SEA41-29 P3")),
         ("chargepoint-snoozed", cpCard("Snoozed", sub: "Place kept",
            keys: [CpKey(command: "rejoin", label: "Rejoin"), CpKey(command: "leave", label: "Leave")],
            deadlineIn: 1605, floors: busy)),
         ("chargepoint-charging", cpCard("7.4", unit: "kWh added", sub: "6.6 kW now",
            keys: [CpKey(command: "stop", label: "Stop")])),
         ("chargepoint-done", cpCard("Done", sub: "Done charging", deadlineIn: 840, goTo: "SEA41-29 P3")),
         ("chargepoint-signed_out", cpCard("Sign in", sub: "Use its own sign-in page", action: "Sign in",
            site: "ChargePoint", account: "Signed out")),
         ("chargepoint-no_location", cpCard("Set up", sub: "Choose a location", action: "Choose location",
            site: "ChargePoint", account: "iredlof")),
         ("chargepoint-cant_join", cpCard("Sign in", sub: "Session expired", action: "Sign in"))]
    }
}

/// Full-screen single-state card for screenshotting (`-parityState <id>`). The card sits at a fixed
/// top-leading offset on black so the capture script can crop it deterministically.
struct ParityStateScreen: View {
    let id: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            (ParityCatalog.view(id) ?? AnyView(Text(id).foregroundStyle(.white)))
                .frame(width: 374, height: 174)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.leading, 16).padding(.top, 70)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}
