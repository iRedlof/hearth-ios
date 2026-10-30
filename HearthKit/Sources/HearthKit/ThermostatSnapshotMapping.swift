import Foundation

/// Maps the raw `ClimateState` (+ discovered sensors / resume) onto the `ThermostatSnapshot` the view renders.
public func thermostatSnapshot(_ s: ClimateState?, name: String, now: Date, stale: Bool,
                               checkedAt: Date?, sensors: [ThermostatSensor] = [], canResume: Bool = false,
                               zone: TimeZone = .current, locale: Locale = .current) -> ThermostatSnapshot {
    let view = climateViewFor(s)
    let (heat, cool) = setpoints(s)
    return ThermostatSnapshot(
        name: name,
        checkedAt: checkedAt.map { climateClock($0, zone, locale) } ?? "—",
        roomTemp: degrees(s?.current),
        roomSub: s?.current == nil ? "No reading" : stale ? "Last known" : "In the room",
        humidity: s?.humidity.map { "\(Int($0.rounded()))% humidity" },
        status: view.headline,
        tone: beaconClimatePair(s?.mode, stale: stale),
        heatSetpoint: heat,
        coolSetpoint: cool,
        mode: s.map { modeDisplay($0.mode) } ?? "—",
        fan: s?.fanMode?.capitalizedFirst,
        canResume: canResume && !stale && s != nil,
        sensors: sensors)
}

private func setpoints(_ s: ClimateState?) -> (heat: String?, cool: String?) {
    guard let s, !s.isOff else { return (nil, nil) }
    if s.isRange { return (s.low.map(degrees), s.high.map(degrees)) }
    if s.mode == "heat" { return (s.target.map(degrees), nil) }
    if s.mode == "cool" { return (nil, s.target.map(degrees)) }
    return (nil, nil)
}

private func modeDisplay(_ mode: String) -> String {
    if let m = CLIMATE_MODES.first(where: { $0.mode == mode }) { return m.name }
    switch mode {
    case "auto": return "Auto"
    case "fan_only": return "Fan"
    case "dry": return "Dry"
    default: return mode.capitalizedFirst
    }
}

private func climateClock(_ date: Date, _ zone: TimeZone, _ locale: Locale) -> String {
    let f = DateFormatter()
    f.locale = locale
    f.timeZone = zone
    f.dateFormat = "h:mm a"
    return f.string(from: date)
}
