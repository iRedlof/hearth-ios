import Foundation

/// What the thermostat is doing, for the status line's meaning. Ported from Android `ClimateTone`.
public enum ClimateTone: String, Sendable { case heating, cooling, idle, off, unknown }

public struct ClimateView: Sendable, Equatable {
    public let headline: String
    public let tone: ClimateTone
    public init(_ headline: String, _ tone: ClimateTone) { self.headline = headline; self.tone = tone }
}

/// The line under the temperature, honestly: what it's doing now if the thermostat says (Heating to 64°),
/// else what it's set to (Holding 64–69°). Ported verbatim from Android `climateViewFor`.
public func climateViewFor(_ s: ClimateState?) -> ClimateView {
    guard let s else { return ClimateView("Checking…", .unknown) }          // nothing read yet
    if s.mode == "unavailable" || s.mode == "unknown" { return ClimateView("Unavailable", .unknown) }
    // Off is what the user set; if still winding down, say so (but stay calm Off — nothing to act on).
    if s.isOff {
        switch s.action {
        case "heating": return ClimateView("Off · still heating", .off)
        case "cooling": return ClimateView("Off · still cooling", .off)
        default:        return ClimateView("Off", .off)
        }
    }
    if !s.isRange && !["heat", "cool"].contains(s.mode) {
        return ClimateView(s.mode.replacingOccurrences(of: "_", with: " ").capitalizedFirst, .idle)
    }
    let missing: String? = {
        if s.isRange && s.low == nil && s.high == nil { return "Targets unavailable" }
        if s.isRange && s.low == nil { return "Heat target unavailable" }
        if s.isRange && s.high == nil { return "Cool target unavailable" }
        if !s.isRange && s.target == nil { return "Target unavailable" }
        return nil
    }()
    if let missing {
        let tone: ClimateTone = s.action == "heating" ? .heating : (s.action == "cooling" ? .cooling : .idle)
        return ClimateView(missing, tone)
    }
    let setTo = s.isRange ? "\(String(degrees(s.low).dropLast()))–\(degrees(s.high))" : degrees(s.target)
    switch s.action {
    case "heating": return ClimateView("Heating to \(s.isRange ? degrees(s.low) : degrees(s.target))", .heating)
    case "cooling": return ClimateView("Cooling to \(s.isRange ? degrees(s.high) : degrees(s.target))", .cooling)
    case "fan":     return ClimateView("Fan only · set \(setTo)", .idle)
    default:        return ClimateView("Holding \(setTo)", .idle)   // idle, or not reported
    }
}

/// The card colour by mode: heat amber, cool blue, auto violet, off/fan/dry slate, stale offline.
/// Ported from Android `beaconClimatePair` (returns the Beacon tone directly here).
public func beaconClimatePair(_ mode: String?, stale: Bool) -> BeaconTone {
    if stale { return .offline }
    switch mode {
    case "heat":              return .yellow
    case "cool":              return .blue
    case "auto", "heat_cool": return .violet
    case "off", "fan_only", "dry": return .slate
    default:                  return .offline
    }
}

/// A setpoint nudged by one step, within the thermostat's limits (and, in Auto, apart from the other).
public func nudge(_ value: Double, by: Int, _ s: ClimateState, otherLow: Double? = nil, otherHigh: Double? = nil) -> Double {
    var next = (value + Double(by) * s.step)
    next = Swift.min(Swift.max(next, s.min), s.max)
    if let otherHigh { next = Swift.min(next, otherHigh - s.step) }   // Auto keeps heat below cool
    if let otherLow { next = Swift.max(next, otherLow + s.step) }
    return next
}
