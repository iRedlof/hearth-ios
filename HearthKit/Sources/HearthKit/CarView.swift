import Foundation

// MARK: - Date helpers (zone/locale injected, so the formatting tests port 1:1)

private func dayDiff(_ from: Date, _ to: Date, _ zone: TimeZone) -> Int {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
    return cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
}

private func dformat(_ date: Date, _ pattern: String, _ zone: TimeZone, _ locale: Locale) -> String {
    let f = DateFormatter(); f.locale = locale; f.timeZone = zone; f.dateFormat = pattern
    return f.string(from: date)
}

/// Integer kW when whole (`7 kW`), else one decimal (`7.5 kW`).
func kwText(_ kw: Double, _ locale: Locale) -> String {
    kw.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kw)) : String(format: "%.1f", kw)
}

private func clock(_ at: Date, _ now: Date, _ zone: TimeZone, _ locale: Locale) -> String {
    dformat(at, dayDiff(now, at, zone) == 0 ? "h:mm a" : "EEE h:mm a", zone, locale)
}

/// "since 9:42 AM" today, "since Mon 9:42 PM" this week, else "since Oct 3". Ported from `AlarmState.kt`.
public func sinceLabel(_ changed: Date?, _ now: Date, _ zone: TimeZone = .current, _ locale: Locale = .current) -> String? {
    guard let changed else { return nil }
    let days = dayDiff(changed, now, zone)
    let pattern = days == 0 ? "h:mm a" : (days >= 1 && days <= 6 ? "EEE h:mm a" : "MMM d")
    return "since " + dformat(changed, pattern, zone, locale)
}

/// Charge ETA: nil unless `at` is strictly after `now`; else "Full by h:mm a" / "Full by EEE h:mm a".
public func beaconCarEta(_ at: Date?, _ now: Date, _ zone: TimeZone = .current, _ locale: Locale = .current) -> String? {
    guard let at, at > now else { return nil }
    return "Full by " + dformat(at, dayDiff(now, at, zone) == 0 ? "h:mm a" : "EEE h:mm a", zone, locale)
}

// MARK: - Car helpers

private let LOW_BATTERY = 20

/// A low battery is only a "charge me" warning when we actually know the car isn't plugged in.
public func carLowBattery(_ car: Car) -> Bool {
    guard let b = car.battery else { return false }
    return b <= LOW_BATTERY && car.pluggedKnown && !car.plugged
}

/// The compact/Beacon charge line, kept parallel to `carView`'s charge logic.
public func carChargeShort(_ car: Car?, withPower: Bool, locale: Locale = .current) -> String {
    guard let car, car.battery != nil else { return "No reading" }
    if ["charging", "starting"].contains(car.chargeState ?? "") {
        return ["Charging", car.chargerKw.flatMap { (withPower && $0 > 0) ? "\(kwText($0, locale)) kW" : nil }]
            .compactMap { $0 }.joined(separator: " · ")
    }
    if car.chargeState == "complete" { return "Charged" }
    if car.plugged { return "Plugged in" }
    if car.pluggedKnown { return "Unplugged" }
    return "Plug status —"
}

/// "<min>–<max>[ unit]" (en-dash U+2013), prefers precise pressures; bar keeps 1 decimal, else rounds.
public func beaconTireSummary(_ car: Car?) -> String {
    guard let car else { return "—" }
    let tires: [Double]
    if let p = car.preciseTires { tires = p }
    else if let t = car.tires { tires = t.map(Double.init) }
    else { return "—" }
    guard let lo = tires.min(), let hi = tires.max() else { return "—" }
    func f(_ n: Double) -> String { car.pressureUnit.lowercased() == "bar" ? String(format: "%.1f", n) : String(Int(n.rounded())) }
    let unit = car.pressureUnit.isEmpty ? "" : " \(car.pressureUnit)"
    return "\(f(lo))\u{2013}\(f(hi))\(unit)"
}

// MARK: - Tone / colour

/// Car state → Beacon tone. Stale or no reading wins (grey); then Alert red; Warn amber; charging blue; else mint.
public func beaconCarPair(_ tone: DoorsTone, charging: Bool, stale: Bool, hasReading: Bool) -> BeaconTone {
    if stale || !hasReading { return .offline }
    switch tone {
    case .alert: return .red
    case .warn: return .yellow
    default: return charging ? .blue : .mint
    }
}

// MARK: - The view model

public func carView(_ car: Car, now: Date, zone: TimeZone = .current, locale: Locale = .current, stale: Bool = false) -> CarView {
    let head = [car.battery.map { "\($0)%" }, car.range.map { "\($0) \(car.unit)" }].compactMap { $0 }.joined(separator: " · ")
    let headline = head.isEmpty ? "No reading" : head
    let limit = car.limit.map { " · limit \($0)%" } ?? ""

    let charging = ["charging", "starting"].contains(car.chargeState ?? "")
    let charge: String
    if charging {
        charge = [
            "Charging",
            car.chargerKw.flatMap { $0 > 0 ? "\(kwText($0, locale)) kW" : nil },
            (car.fullAt.flatMap { $0 > now ? "full at \(clock($0, now, zone, locale))" : nil }) ?? car.limit.map { "to \($0)%" },
        ].compactMap { $0 }.joined(separator: " · ")
    } else if car.chargeState == "complete" {
        charge = car.limit.map { "Charged to \($0)%" } ?? "Charged"
    } else if car.plugged {
        charge = "Plugged in, not charging\(limit)"
    } else if !car.pluggedKnown {
        charge = "Plug status unknown\(limit)"
    } else {
        charge = "Not plugged in\(limit)"
    }

    let unlocked = car.locked == false
    let tone: DoorsTone
    if unlocked && car.place != "Home" { tone = .alert }
    else if unlocked || !car.open.isEmpty || car.tireWarning || carLowBattery(car) { tone = .warn }
    else { tone = .calm }

    var facts: [CarFact] = []
    if let locked = car.locked { facts.append(locked ? CarFact(.lock, "Locked") : CarFact(.lock, "Unlocked", bad: true)) }
    if !car.open.isEmpty { facts.append(CarFact(.closed, car.open.joined(separator: ", ") + " open", bad: true)) }
    else if car.openKnown { facts.append(CarFact(.closed, "All shut")) }
    else { facts.append(CarFact(.closed, "Openings unknown")) }
    if car.tireWarning { facts.append(CarFact(.tires, "Check tires", bad: true)) }
    if let inside = car.inside {
        facts.append(CarFact(.inside, ["\(inside)° in", car.outside.map { "\($0)° out" }].compactMap { $0 }.joined(separator: " · ")))
    }

    let subline: String
    if charging {
        subline = [
            "Charging" + (car.chargerKw.flatMap { $0 > 0 ? " \(kwText($0, locale)) kW" : nil } ?? ""),
            car.fullAt.flatMap { $0 > now ? "full by \(clock($0, now, zone, locale))" : nil },
        ].compactMap { $0 }.joined(separator: " · ")
    } else {
        subline = [car.range.map { "\($0) \(car.unit)" }, car.place].compactMap { $0 }.joined(separator: " · ")
    }

    let asOf: String?
    if stale {
        let from = sinceLabel(car.since, now, zone, locale).map { " · these are from " + ($0.hasPrefix("since ") ? String($0.dropFirst(6)) : $0) } ?? ""
        asOf = "No new readings from the car" + from
    } else {
        switch car.awake {
        case .some(true): asOf = "Awake"
        case .some(false): asOf = sinceLabel(car.since, now, zone, locale).map { "Asleep \($0)" } ?? "Asleep"
        case .none: asOf = nil
        }
    }

    let tiresStr: String? = car.tires.flatMap { t in
        guard t.count == 4 else { return nil }
        return "Tires \(t[0]) · \(t[1]) front, \(t[2]) · \(t[3]) rear \(car.pressureUnit)".trimmingCharacters(in: .whitespaces)
    }

    return CarView(headline: headline, charge: charge, tone: tone, facts: facts, asOf: asOf,
                   tires: tiresStr, subline: subline, charging: charging, sentry: car.sentry)
}

// MARK: - Layout sizing

public let CAR_PANEL_DP: Float = 72
private let CAR_PANEL_GAP_DP: Float = 8
private func dashboardDp(_ fontScale: Float) -> Float { 54 + 228 * max(1, fontScale) }

public func carPanelRows(_ roomDp: Float, _ fontScale: Float) -> Int {
    min(max(Int(roomDp / (CAR_PANEL_DP * max(1, fontScale) + CAR_PANEL_GAP_DP)), 0), 2)
}

public func carLayout(_ innerWidthDp: Float, _ heightDp: Float, _ fontScale: Float) -> CarLayout {
    if innerWidthDp < 300 { return .ring }
    if heightDp - 28 >= dashboardDp(fontScale) { return .dashboard }
    return .hero
}
