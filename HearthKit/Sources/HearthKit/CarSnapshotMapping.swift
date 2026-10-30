import Foundation

private func numberFmt(_ n: Double) -> String {
    n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(format: "%.1f", n)
}

private func hmma(_ date: Date, _ zone: TimeZone, _ locale: Locale) -> String {
    let f = DateFormatter(); f.locale = locale; f.timeZone = zone; f.dateFormat = "h:mm a"
    return f.string(from: date)
}

/// Maps the raw `Car` (+ `carView`) onto the formatted `CarSnapshot` the SwiftUI Beacon view renders,
/// reproducing the Android `CarWidget` v1.4.28 display logic (left status rows, the right-panel location/
/// sentry/charge line, and the tone). `checkedAt`/`stale` come from the refresh layer.
public func carSnapshot(_ car: Car?, now: Date, stale: Bool, checkedAt: Date?,
                        zone: TimeZone = .current, locale: Locale = .current) -> CarSnapshot {
    let checkedStr = checkedAt.map { hmma($0, zone, locale) } ?? "—"

    guard let car else {
        let msg = checkedAt == nil ? "Finding your car…" : "No car found"
        return CarSnapshot(name: "Car", checkedAt: checkedStr, battery: nil, range: "Range —",
            lock: "—", lockWarn: false, doors: "—", doorsWarn: false, cabin: "—", outside: "—",
            tires: "—", tiresWarn: false, place: msg, sentry: .unknown, chargeLine: msg, tone: .offline, stale: stale)
    }

    let view = carView(car, now: now, zone: zone, locale: locale, stale: stale)

    let range = car.range.map { "\($0) \(car.unit) range" } ?? "Range —"
    let lock = car.locked.map { $0 ? "Locked" : "Unlocked" } ?? "—"
    let doors = car.open.isEmpty ? (car.openKnown ? "All shut" : "—") : car.open.joined(separator: ", ") + " open"

    func temp(_ precise: Double?, _ whole: Int?) -> String {
        guard let v = precise ?? whole.map(Double.init) else { return "—" }
        return numberFmt(v) + (car.tempUnit.isEmpty ? "°" : car.tempUnit)
    }

    // Location line: "<place> · <age>", where age = "Last known" (stale) or the asOf line with
    // "Asleep since" lower-cased to "asleep since" (matches the Android location row).
    let age: String? = stale ? "Last known"
        : view.asOf.map { $0.replacingOccurrences(of: "Asleep since", with: "asleep since") }
    var place = [car.place, age].compactMap { $0 }.joined(separator: " · ")
    if place.isEmpty { place = car.battery == nil ? "Waiting for readings" : "" }

    let sentry: SentryState = car.sentryKnown ? (car.sentry ? .on : .off) : .unknown

    // Charge line (v1.4.28 priority): warning > ETA > charge state.
    let eta = (view.charging && !stale) ? beaconCarEta(car.fullAt, now, zone, locale) : nil
    let chargeLine: String
    if stale { chargeLine = "Last known" }
    else if car.tireWarning { chargeLine = "Check tires" }
    else if carLowBattery(car) { chargeLine = "Low battery" }
    else if let eta { chargeLine = eta }
    else { chargeLine = carChargeShort(car, withPower: true, locale: locale) }

    let tone = beaconCarPair(view.tone, charging: view.charging, stale: stale, hasReading: car.battery != nil)

    return CarSnapshot(
        name: car.name, checkedAt: checkedStr, battery: car.battery, range: range,
        lock: lock, lockWarn: car.locked == false,
        doors: doors, doorsWarn: !car.open.isEmpty,
        cabin: temp(car.preciseInside, car.inside), outside: temp(car.preciseOutside, car.outside),
        tires: beaconTireSummary(car), tiresWarn: car.tireWarning,
        place: place, sentry: sentry, chargeLine: chargeLine, tone: tone, limit: car.limit, stale: stale)
}
