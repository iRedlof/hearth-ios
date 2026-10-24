import Foundation

public enum ClimateSide: String, Sendable { case heat, cool }

/// The `climate.set_temperature` payload for a one-step nudge of a setpoint — honouring range vs
/// single mode and the thermostat's limits (via the existing `nudge`). Returns nil when no valid
/// command can be formed (missing targets). Mirrors Android `ClimateRepository.nudgeTarget`.
public func setpointNudge(_ s: ClimateState, side: ClimateSide, by step: Int) -> [String: Double]? {
    guard s.canSetTemperature else { return nil }
    if s.isRange {
        guard let low = s.low, let high = s.high else { return nil }
        if side == .heat {
            return ["target_temp_low": nudge(low, by: step, s, otherHigh: high), "target_temp_high": high]
        }
        return ["target_temp_low": low, "target_temp_high": nudge(high, by: step, s, otherLow: low)]
    }
    guard let target = s.target else { return nil }
    return ["temperature": nudge(target, by: step, s)]
}
