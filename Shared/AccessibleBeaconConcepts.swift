#if DEBUG
import SwiftUI
import UIKit
import HearthKit

/// Inert layout proofs. These contain example readings, never a live route or command origin.
struct AccessibleBeaconConcept: Identifiable {
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }
    struct Section: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }
    struct Control: Identifiable {
        let title: String
        let symbol: String
        var reason: String?
        var id: String { title }
    }
    let id: String
    let identity: String
    let primary: String
    let numeric: Bool
    let tone: BeaconTone
    let navigation: String
    let accessibilityContext: String
    let sections: [Section]
    let controls: [Control]
    var carImage = false
    var nativeID: String {
        let pieces = id.components(separatedBy: "-readable-")
        return "readable-\(pieces[0])-\(pieces[1])"
    }
}

@MainActor enum AccessibleBeaconConceptCatalog {
    static let referenceDate = Date(timeIntervalSince1970: 1_793_475_600)

    static var concepts: [AccessibleBeaconConcept] {
        ["parked", "charging", "open", "unlocked_away", "tires", "low_battery",
         "stale_sentry", "no_car", "setup", "auth_failed"].map(car)
        + ["disarmed", "armed_home", "armed_away", "triggered", "triggered_door_failure",
           "door_open", "panel_unknown", "offline", "pending_arm", "setup", "auth_failed", "long_names"].map(alarm)
        + ["auto", "off", "sensor_failed", "offline", "unknown_room", "setup", "auth_failed",
           "bad_entity", "long_names"].map(thermostat)
        + ["available", "waiting", "waiting_unknown", "offer", "offer_last", "held",
           "snoozed", "charging", "expired", "unknown_deadline", "working", "signed_out",
           "cant_join", "no_location"].map(chargePoint)
    }

    static func concept(_ id: String) -> AccessibleBeaconConcept? {
        concepts.first { $0.id == id }
    }

    private static func car(_ state: String) -> AccessibleBeaconConcept {
        let s = CarParityInputs.snapshot(state)
        let answer: String
        if s.needsSignIn { answer = "Sign in" }
        else if state == "setup" { answer = "Set up" }
        else if s.stale { answer = "Last known" }
        else if state == "no_car" { answer = "No car" }
        else if s.doorsWarn { answer = "Open" }
        else if s.lockWarn { answer = "Unlocked" }
        else if s.tiresWarn { answer = "Check tires" }
        else if state == "low_battery" { answer = "Low battery" }
        else if state == "charging" { answer = "Charging" }
        else { answer = s.battery.map { "\($0)%" } ?? "No reading" }
        let historical = s.stale ? "Last known · " : ""
        return .init(id: "car-readable-\(state)", identity: s.name, primary: answer,
            numeric: answer.hasSuffix("%"), tone: s.tone, navigation: "readings",
            accessibilityContext: "\(historical)\(s.place). \(historical)\(s.doors). \(s.chargeLine).",
            sections: [
                .init(title: "Reading", rows: [
                    .init(label: "Status", value: s.chargeLine),
                    .init(label: "Checked", value: s.checkedAt),
                    .init(label: "Battery", value: historical + (s.battery.map { "\($0)%" } ?? "Unknown")),
                    .init(label: "Range", value: historical + s.range),
                    .init(label: "Charge limit", value: s.limit.map { historical + "\($0)%" } ?? "Unknown"),
                    .init(label: "Location", value: historical + s.place)]),
                .init(title: "Security", rows: [
                    .init(label: "Lock", value: historical + s.lock),
                    .init(label: "Openings", value: historical + s.doors),
                    .init(label: "Sentry", value: historical + (s.sentry == .unknown ? "Unknown" : s.sentry == .on ? "On" : "Off"))]),
                .init(title: "Conditions", rows: [
                    .init(label: "Cabin", value: historical + s.cabin),
                    .init(label: "Outside", value: historical + s.outside),
                    .init(label: "Tires", value: historical + s.tires)]),
                .init(title: "Feedback", rows: [.init(label: "Reading error", value: s.error ?? "None")])
            ],
            controls: [.init(title: "Refresh", symbol: "arrow.clockwise"),
                       .init(title: s.needsSignIn ? "Sign in" : s.needsSettings ? "Open Settings" : "Open Tesla",
                             symbol: "arrow.up.right")],
            carImage: true)
    }

    private static func alarm(_ state: String) -> AccessibleBeaconConcept {
        var s = AlarmParityInputs.snapshot(state == "triggered_door_failure" ? "triggered" : state)
        if state == "triggered_door_failure" {
            s.doorStale = true
            s.doorError = "Signed out: sign in again"
            s.needsSignIn = true
            s.doorAction = nil
        }
        let answer: String
        if !s.stale && s.stateWord == "Alarm triggered" { answer = "Alarm!" }
        else if s.doorSelected && !s.doorStale && s.doorError == nil && s.doorLocked == false {
            answer = s.doorState
        } else if s.setup { answer = "Set up" }
        else if beaconNeedsSignIn(s.error) { answer = "Sign in" }
        else if s.stale { answer = "Last known" }
        else { answer = s.stateWord }
        var controls = s.actionSlots.map {
            AccessibleBeaconConcept.Control(title: $0.label,
                symbol: $0 == .armAway ? "car" : $0 == .armHome ? "house" : "shield.slash",
                reason: !s.actions.contains($0) || s.commandPending ? "Unavailable in this state" : nil)
        }
        if let action = s.doorAction {
            controls.append(.init(title: action.label + " " + s.doorName, symbol: "lock"))
        }
        if s.needsSignIn { controls.append(.init(title: "Sign in", symbol: "person.crop.circle")) }
        else if s.setup { controls.append(.init(title: "Connect Home Assistant", symbol: "house")) }
        else if s.needsSettings || !s.doorSelected { controls.append(.init(title: "Open Settings", symbol: "gearshape")) }
        controls.append(.init(title: "Refresh", symbol: "arrow.clockwise"))
        let alarmState = (s.stale ? "Last known · " : "") + s.stateWord
        return .init(id: "alarm-readable-\(state)", identity: s.name, primary: answer,
            numeric: false, tone: s.tone, navigation: "controls",
            accessibilityContext: "Alarm \(alarmState). \(s.doorName), \(s.doorStale ? "last known" : "") \(s.doorState).",
            sections: [
                .init(title: "Alarm", rows: [
                    .init(label: "State", value: alarmState),
                    .init(label: "Since", value: s.detail),
                    .init(label: "Checked", value: s.checkedAt),
                    .init(label: "Reading error", value: s.error ?? "None"),
                    .init(label: "Command", value: s.commandFeedback ?? s.commandError ?? "No pending command")]),
                .init(title: s.doorName, rows: [
                    .init(label: "Door", value: (s.doorStale ? "Last known · " : "") + s.doorState),
                    .init(label: "Since", value: s.doorSince ?? "Unknown"),
                    .init(label: "Reading error", value: s.doorError ?? "None")])
            ], controls: controls)
    }

    private static func thermostat(_ state: String) -> AccessibleBeaconConcept {
        let s = ThermostatParityInputs.snapshot(state)
        let answer = s.setup ? "Set up" : s.needsSignIn ? "Sign in" : s.stale ? "Last known"
            : s.mode == "Off" ? "Off" : s.roomTemp == "—" ? "No reading" : s.roomTemp
        var controls: [AccessibleBeaconConcept.Control] = []
        for (title, value, down, up) in [
            ("Heat", s.heatSetpoint, s.canAdjustHeatDown, s.canAdjustHeatUp),
            ("Cool", s.coolSetpoint, s.canAdjustCoolDown, s.canAdjustCoolUp)
        ] where value != nil {
            controls.append(.init(title: "Decrease \(title.lowercased()) target", symbol: "minus",
                                  reason: down ? nil : "Unavailable at this target or state"))
            controls.append(.init(title: "Increase \(title.lowercased()) target", symbol: "plus",
                                  reason: up ? nil : "Unavailable at this target or state"))
        }
        if s.needsSignIn { controls.append(.init(title: "Sign in", symbol: "person.crop.circle")) }
        else if s.setup { controls.append(.init(title: "Connect Home Assistant", symbol: "house")) }
        else if s.needsSettings { controls.append(.init(title: "Open Settings", symbol: "gearshape")) }
        else {
            controls.append(.init(title: "Choose mode", symbol: "thermometer",
                                  reason: s.canPickMode ? nil : "No available mode change"))
        }
        if s.hasFanControl { controls.append(.init(title: "Choose fan", symbol: "fan",
                                                  reason: s.canPickFan ? nil : "No available fan change")) }
        if s.hasResumeControl { controls.append(.init(title: "Resume schedule", symbol: "clock",
                                                     reason: s.canResume ? nil : "Unavailable in this state")) }
        controls.append(.init(title: "Refresh", symbol: "arrow.clockwise"))
        let historical = s.stale ? "Last known · " : ""
        return .init(id: "thermostat-readable-\(state)", identity: s.name, primary: answer,
            numeric: answer.contains("°"), tone: s.tone, navigation: "controls",
            accessibilityContext: "\(s.status). Room \(historical)\(s.roomTemp). Mode \(historical)\(s.mode).",
            sections: [
                .init(title: "Thermostat", rows: [
                    .init(label: "Room", value: historical + s.roomTemp),
                    .init(label: "Reading", value: s.roomSub),
                    .init(label: "Mode", value: historical + s.mode),
                    .init(label: "Status", value: s.status),
                    .init(label: "Humidity", value: s.humidity.map { historical + $0 } ?? "Unknown"),
                    .init(label: "Checked", value: s.checkedAt),
                    .init(label: "Reading error", value: s.error ?? "None"),
                    .init(label: "Command", value: s.commandFeedback ?? s.commandError ?? "No pending command")]),
                .init(title: "Targets", rows: [
                    .init(label: "Heat", value: s.heatSetpoint.map { historical + $0 } ?? "No target"),
                    .init(label: "Cool", value: s.coolSetpoint.map { historical + $0 } ?? "No target"),
                    .init(label: "Fan", value: s.fan.map { historical + $0 }
                          ?? (s.setup || s.stale ? "Unknown" : "Unsupported"))]),
                .init(title: "Selected sensors", rows: s.sensors.map {
                    .init(label: $0.name, value: ($0.stale ? "Last known · " : "") + $0.value)
                })
            ], controls: controls)
    }

    private static func chargePoint(_ name: String) -> AccessibleBeaconConcept {
        let phases = ["waiting": "WAITING", "waiting_unknown": "WAITING", "offer": "ACCEPT_PENDING",
                      "offer_last": "ACCEPT_PENDING", "held": "PENDING_PLUG_IN", "snoozed": "PASS",
                      "charging": "CHARGING", "expired": "ACCEPT_PENDING",
                      "unknown_deadline": "ACCEPT_PENDING", "working": "ACCEPT_PENDING"]
        let phase = phases[name]
        let site = ["signed_out", "no_location"].contains(name) ? nil :
            CpLocation(name: "Amazon Day 1", address: "", deviceIds: [1, 2],
                       bounds: cpBounds(lat: 0, lon: 0))
        let deadline = name == "unknown_deadline" ? 0 :
            Int64(referenceDate.addingTimeInterval(name == "expired" ? -1 : 833).timeIntervalSince1970 * 1000)
        let offer = CpOffer(deviceId: 1, port: 1, charger: "SEA41 - 29 P3", untilMs: deadline,
                            startMs: Int64(referenceDate.addingTimeInterval(600).timeIntervalSince1970 * 1000))
        let state = CpState(signedOut: name == "signed_out",
            account: cpAccount(hasSession: name != "signed_out", expired: false, joinExpired: name == "cant_join"),
            location: site, now: site == nil ? nil : CpNow(free: 12, inUse: 7, offline: 1, stations: 10),
            waitlist: phase.map { .inLine(place: name == "waiting" ? 3 : nil, state: $0,
                                         stations: 10, offer: offer, auto: false) } ?? .notQueued,
            charging: name == "charging" ? CpCharging(sessionId: 9, powerKw: 6.6, energyKwh: 7.4,
                                                      minutes: 65, canStop: true) : nil,
            autoOn: ["waiting", "held", "snoozed", "working"].contains(name),
            floors: [CpFloor(level: "P2", free: 4, total: 10), CpFloor(level: "P3", free: 8, total: 10)],
            snoozesLeft: name == "offer_last" ? 0 : 1)
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US")
        clock.timeZone = .current
        clock.dateFormat = "h:mm a"
        var s = cpSnapshot(state, email: "iredlof@example.com",
                           checkedAt: clock.string(from: referenceDate), now: referenceDate)
        if name == "working" {
            s = cpApplyingOperation(s, CpOperation(command: "accept", startedAt: referenceDate), now: referenceDate)
        }
        let timed = ["offer", "offer_last", "held", "snoozed", "working"].contains(name)
        let answer: String
        if name == "expired" { answer = "Expired" }
        else if name == "unknown_deadline" { answer = "Your turn" }
        else if timed && s.deadline != nil { answer = "13:53" }
        else if name == "available" { answer = "12 free" }
        else if name == "waiting_unknown" { answer = "In line" }
        else if name == "charging" { answer = "7.4 kWh" }
        else if name == "cant_join" { answer = "View only" }
        else if name == "no_location" { answer = "Set up" }
        else { answer = s.bigAnswer }
        let purpose = phase == "ACCEPT_PENDING" ? "to accept" : phase == "PASS" ? "until rejoining"
            : phase == "PENDING_PLUG_IN" ? "to plug in" : s.unit
        let autoTitle = s.autoControl == .signin ? "Sign in to use Auto" : s.autoControl == .stop ? "Stop Auto"
            : s.autoControl == .join ? "Join and start Auto" : "Resume Auto"
        let autoState = s.autoControl == .signin ? "Unavailable · sign in"
            : s.autoControl == .disabled ? "Unavailable in this state" : s.autoOn ? "On" : "Off"
        let controls = s.keys.map { key in
            AccessibleBeaconConcept.Control(title: key.label, symbol: "bolt",
                reason: s.working ? "Another command is pending"
                    : ["accept", "snooze"].contains(key.command) && ["expired", "unknown_deadline"].contains(name)
                        ? "Refresh to confirm the assignment and deadline" : nil)
        }
            + (s.keys.isEmpty ? [.init(title: s.actionLabel, symbol: "arrow.up.right")] : [])
            + (s.showOpen && !s.keys.contains { $0.command == "open" }
                ? [.init(title: "Open ChargePoint", symbol: "arrow.up.right")] : [])
            + (s.autoControl == .disabled ? [] : [.init(title: autoTitle, symbol: "playpause")])
            + [.init(title: "Refresh", symbol: "arrow.clockwise")]
        return .init(id: "chargepoint-readable-\(name)", identity: s.site, primary: answer,
            numeric: timed || name == "charging" || name == "available", tone: .orange, navigation: "controls",
            accessibilityContext: "\(s.account). Auto \(autoState). \(answer) \(purpose). \(s.sub).",
            sections: [
                .init(title: "Account and site", rows: [
                    .init(label: "Site", value: s.site),
                    .init(label: "Account", value: s.account == "Signed out" ? "Signed out" : "iredlof@example.com"),
                    .init(label: "Auto", value: autoState),
                    .init(label: "Checked", value: s.checkedAt)]),
                .init(title: "Assignment", rows: [
                    .init(label: "Phase", value: phase ?? s.bigAnswer),
                    .init(label: "Time", value: timed ? "13:53 \(purpose)" : s.sub),
                    .init(label: "Charger", value: s.goTo ?? "No assignment"),
                    .init(label: "Allowance", value: s.railNotes.joined(separator: "\n")),
                    .init(label: "Command", value: s.working ? s.sub : "No pending command")]),
                .init(title: "Availability", rows: s.floors.map {
                    .init(label: $0.level, value: "\($0.free) of \($0.total) free")
                }),
                .init(title: "Session", rows: s.stats.map { .init(label: $0.label, value: $0.value) })
            ], controls: controls)
    }
}

/// The actual native text environment drives this layout; no Dynamic Type cap or text shrink.
struct AccessibleBeaconConceptView: View {
    let concept: AccessibleBeaconConcept
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .caption) private var identitySize: CGFloat = 13

    var body: some View {
        HStack(spacing: 0) {
            Color(argb: concept.tone.fillARGB).frame(width: 12).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: dynamicType.isAccessibilitySize ? 6 : 8) {
                if !dynamicType.isAccessibilitySize {
                    Text(concept.identity).font(.system(size: identitySize, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color(argb: BeaconSurfaceColors.softARGB))
                }
                Text(concept.primary)
                    .font(primaryFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { geometry in
                            let _ = ParityCatalog.recordReadableTextFrame(concept.nativeID, size: geometry.size)
                            Color.clear
                        }
                    }
                navigation
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .foregroundStyle(Color(argb: BeaconSurfaceColors.inkARGB))
        .background(LinearGradient(colors: [Color(argb: 0xFF303A32), Color(argb: 0xFF202722)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(ContainerRelativeShape().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .accessibilityIdentifier(concept.id)
    }

    /// Resolve a concrete font with the incoming category before WidgetKit archives the view.
    /// Semantic Font tokens can retain ordinary-size metrics in the widget text renderer.
    private var contentSizeCategory: UIContentSizeCategory {
        switch dynamicType {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

    private var primaryFont: Font {
        let style: UIFont.TextStyle = concept.numeric ? .title3 : .body
        let base = concept.numeric
            ? UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)
            : UIFont.systemFont(ofSize: 17, weight: .bold)
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)))
    }

    private var navigationFont: Font {
        Font(UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: 15, weight: .semibold),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)))
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            Text(dynamicType.isAccessibilitySize ? concept.navigation.capitalized : "Open \(concept.navigation)")
            Image(systemName: "chevron.right").accessibilityHidden(true)
        }
        .font(navigationFont)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(LinearGradient(colors: [Color(argb: 0xFF465249), Color(argb: 0xFF2D372F)],
                                   startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(concept.identity). \(concept.primary). \(concept.accessibilityContext) Open \(concept.navigation == "readings" ? "readings" : "controls and readings"). Design prototype.")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
