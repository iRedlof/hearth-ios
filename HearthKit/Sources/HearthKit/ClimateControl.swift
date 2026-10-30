import Foundation

public enum ClimateSide: String, Sendable { case heat, cool }

/// The `climate.set_temperature` payload for a one-step nudge of a setpoint — honouring range vs
/// single mode and the thermostat's limits (via the existing `nudge`). Returns nil when no valid
/// command can be formed (missing targets). Mirrors Android `ClimateRepository.nudgeTarget`.
public func setpointNudge(_ s: ClimateState, side: ClimateSide, by step: Int) -> [String: Double]? {
    guard s.canSetTemperature, step == -1 || step == 1 else { return nil }
    if s.isRange {
        guard let low = s.low, let high = s.high else { return nil }
        if side == .heat {
            let next = nudge(low, by: step, s, otherHigh: high)
            guard next != low, next >= s.min, next <= s.max, next + s.step <= high else { return nil }
            return ["target_temp_low": next, "target_temp_high": high]
        }
        let next = nudge(high, by: step, s, otherLow: low)
        guard next != high, next >= s.min, next <= s.max, low + s.step <= next else { return nil }
        return ["target_temp_low": low, "target_temp_high": next]
    }
    guard s.mode == side.rawValue, let target = s.target else { return nil }
    let next = nudge(target, by: step, s)
    guard next != target, next.isFinite else { return nil }
    return ["temperature": next]
}

public func climateOptions(_ s: ClimateState, kind: String) -> [String] {
    guard s.isAvailable else { return [] }
    return climateAdvertisedOptions(s, kind: kind)
}

/// Metadata determines stable control slots, even while the thermostat is unavailable.
public func climateAdvertisedOptions(_ s: ClimateState, kind: String) -> [String] {
    guard ["mode", "fan"].contains(kind) else { return [] }
    var seen = Set<String>()
    let hvacModes = ["off", "heat", "cool", "auto", "heat_cool", "fan_only", "dry"]
    return (kind == "fan" ? s.fanModes : s.modes).compactMap {
        let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !["null", "unknown", "unavailable"].contains(value.lowercased()),
              kind == "fan" || hvacModes.contains(value), seen.insert(value).inserted else { return nil }
        return value
    }
}

/// A single option remains useful when it differs from the current setting.
public func climateNextOption(_ s: ClimateState, kind: String) -> String? {
    let options = climateOptions(s, kind: kind)
    guard !options.isEmpty else { return nil }
    let current = kind == "fan" ? s.fanMode : s.mode
    let index = current.flatMap { options.firstIndex(of: $0) } ?? -1
    let next = options[(index + 1) % options.count]
    return next == current ? nil : next
}
