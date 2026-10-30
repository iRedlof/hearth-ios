import Foundation

/// The thermostat as Home Assistant reports it (`climate.*`): what it's set to (mode, targets, fan)
/// and what it's doing (heating/cooling/fan/idle). Ported from Android `ClimateState.kt`.
public struct ClimateState: Sendable, Equatable {
    public var mode: String        // off | heat | cool | heat_cool | auto | fan_only | dry
    public var action: String?     // heating | cooling | fan | idle | off | drying, if reported
    public var current: Double?
    public var humidity: Double?
    public var target: Double?     // heat / cool: one setpoint
    public var low: Double?        // heat_cool: heat to
    public var high: Double?       // heat_cool: cool to
    public var fanMode: String?
    public var fanModes: [String]
    public var modes: [String]
    public var min: Double
    public var max: Double
    public var step: Double
    public var lastChanged: Date?

    public init(mode: String, action: String?, current: Double?, humidity: Double?, target: Double?,
                low: Double?, high: Double?, fanMode: String?, fanModes: [String], modes: [String],
                min: Double, max: Double, step: Double, lastChanged: Date?) {
        self.mode = mode; self.action = action; self.current = current; self.humidity = humidity
        self.target = target; self.low = low; self.high = high; self.fanMode = fanMode
        self.fanModes = fanModes; self.modes = modes; self.min = min; self.max = max
        self.step = step; self.lastChanged = lastChanged
    }

    public var isRange: Bool { mode == "heat_cool" || mode == "auto" }
    public var isOff: Bool { mode == "off" }
    public var isAvailable: Bool { ["off", "heat", "cool", "heat_cool", "auto", "fan_only", "dry"].contains(mode) }
    /// A range command sends both values; a partial reading cannot form that command.
    public var canSetTemperature: Bool {
        guard climateNumber(min) != nil, climateNumber(max) != nil, min < max,
              step.isFinite, step > 0, step <= max - min else { return false }
        func valid(_ value: Double?) -> Bool {
            guard let value = climateNumber(value) else { return false }
            return value >= min && value <= max
        }
        if isRange {
            guard valid(low), valid(high), let low, let high else { return false }
            return high - low >= step
        }
        return ["heat", "cool"].contains(mode) && valid(target)
    }

    public static func fromJson(_ body: String) -> ClimateState? {
        guard let data = body.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let mode = o["state"] as? String else { return nil }
        let a = (o["attributes"] as? [String: Any]) ?? [:]
        func num(_ k: String) -> Double? {
            guard let v = a[k], !(v is NSNull) else { return nil }
            let d = (v as? NSNumber)?.doubleValue
            return (d?.isFinite == true) ? d : nil
        }
        func list(_ k: String) -> [String] { (a[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
        func str(_ k: String) -> String? {
            guard let s = a[k] as? String, !s.isEmpty, s != "null" else { return nil }
            return s
        }
        return ClimateState(
            mode: mode,
            action: str("hvac_action"),
            current: num("current_temperature"),
            humidity: num("current_humidity"),
            target: num("temperature"),
            low: num("target_temp_low"),
            high: num("target_temp_high"),
            fanMode: str("fan_mode"),
            fanModes: list("fan_modes"),
            modes: list("hvac_modes"),
            min: num("min_temp") ?? 45.0,
            max: num("max_temp") ?? 95.0,
            step: num("target_temp_step") ?? 1.0,
            lastChanged: parseOffsetDateTime(o["last_changed"] as? String)
        )
    }
}

/// The thermostat's modes in the order the widget shows them, with their plain names.
public let CLIMATE_MODES: [(mode: String, name: String)] =
    [("off", "Off"), ("heat", "Heat"), ("cool", "Cool"), ("heat_cool", "Auto")]

/// "69°", "69.5°" (no trailing .0), "—" for nil.
public func degrees(_ t: Double?) -> String {
    guard let t = climateNumber(t) else { return "—" }
    if t.truncatingRemainder(dividingBy: 1.0) == 0 { return "\(Int(exactly: t.rounded())!)°" }
    return String(format: "%.1f°", t)
}

/// Reject non-finite and unrepresentable readings before integer formatting or control arithmetic.
func climateNumber(_ value: Double?) -> Double? {
    guard let value, value.isFinite, Int(exactly: value.rounded()) != nil else { return nil }
    return value
}

extension String {
    /// Capitalise only the first character (Kotlin's `replaceFirstChar(Char::uppercase)`), e.g. "fan only" -> "Fan only".
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
