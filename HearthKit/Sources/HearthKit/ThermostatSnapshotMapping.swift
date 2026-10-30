import Foundation

/// Maps the raw `ClimateState` (+ discovered sensors / resume) onto the `ThermostatSnapshot` the view renders.
public func thermostatSnapshot(_ s: ClimateState?, name: String, now: Date, stale: Bool,
                               checkedAt: Date?, sensors: [ThermostatSensor] = [], canResume: Bool = false,
                               zone: TimeZone = .current, locale: Locale = .current) -> ThermostatSnapshot {
    let view = climateViewFor(s)
    let (heat, cool) = setpoints(s)
    let historical = stale || s?.isAvailable == false
    var snapshot = ThermostatSnapshot(
        name: name,
        checkedAt: checkedAt.map { climateClock($0, zone, locale) } ?? "—",
        roomTemp: degrees(s?.current),
        roomSub: climateNumber(s?.current) == nil ? "No reading" : historical ? "Last known" : "In the room",
        humidity: s?.humidity.flatMap { h in
            guard h.isFinite, h >= 0, h <= 100, let n = Int(exactly: h.rounded()) else { return nil }
            return "\(n)% humidity"
        },
        status: stale ? "Last known" : view.headline,
        tone: beaconClimatePair(s?.mode, stale: historical),
        heatSetpoint: heat,
        coolSetpoint: cool,
        mode: s.map { modeDisplay($0.mode) } ?? "—",
        fan: s?.fanMode?.capitalizedFirst,
        canResume: canResume && !historical && s?.isAvailable == true,
        sensors: sensors)
    snapshot.stale = historical
    snapshot.hasResumeControl = canResume
    snapshot.hasFanControl = s.map { $0.fanMode != nil || !climateAdvertisedOptions($0, kind: "fan").isEmpty } ?? false
    if let s, !historical {
        snapshot.canAdjustHeatUp = setpointNudge(s, side: .heat, by: 1) != nil
        snapshot.canAdjustHeatDown = setpointNudge(s, side: .heat, by: -1) != nil
        snapshot.canAdjustCoolUp = setpointNudge(s, side: .cool, by: 1) != nil
        snapshot.canAdjustCoolDown = setpointNudge(s, side: .cool, by: -1) != nil
        snapshot.canPickMode = climateNextOption(s, kind: "mode") != nil
        snapshot.canPickFan = climateNextOption(s, kind: "fan") != nil
    }
    return snapshot
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
