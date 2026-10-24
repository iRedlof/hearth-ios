import Foundation

/// Every replaceable battery (a `%` battery sensor), excluding self-charging integrations (phones,
/// the car, vacuum, powerwall). Ported verbatim from Android `BatteryState.kt`.
public let BATTERY_TEMPLATE = """
{%- set ns = namespace(skip=[], l=[]) -%}
{%- for i in ['mobile_app', 'tesla_custom', 'tesla_fleet', 'teslemetry', 'tessie', 'roborock', 'tesla_wall_connector', 'powerwall'] -%}{%- set ns.skip = ns.skip + integration_entities(i) -%}{%- endfor -%}
{%- for s in states.sensor if s.attributes.device_class == 'battery' and s.attributes.unit_of_measurement == '%' and s.state | is_number and s.entity_id not in ns.skip -%}
{%- set ns.l = ns.l + [{'id': s.entity_id, 'name': s.name, 'level': s.state | float}] -%}
{%- endfor -%}
{{ ns.l | to_json }}
"""

public let BATTERY_LOW = 30
public let BATTERY_EMPTY = 10

/// Card colours for the non-Beacon status tone (green / amber / red / grey). `DoorsTone` itself is
/// defined in Car.swift and shared across the non-Beacon widgets.
public extension DoorsTone {
    var fillARGB: UInt32 {
        switch self { case .calm: 0xFFD6EEDF; case .warn: 0xFFF6E7C6; case .alert: 0xFFF3D4D4; case .unknown: 0xFFE2E6E3 }
    }
    var inkARGB: UInt32 {
        switch self { case .calm: 0xFF143221; case .warn: 0xFF3B2E10; case .alert: 0xFF4A1414; case .unknown: 0xFF2A2E2B }
    }
}

public struct Battery: Sendable, Equatable {
    public let id: String; public let name: String; public let level: Int
    public init(id: String, name: String, level: Int) { self.id = id; self.name = name; self.level = level }
}

public struct BatteryRow: Sendable, Equatable {
    public let name: String; public let level: Int; public let low: Bool; public let empty: Bool
    public init(name: String, level: Int, low: Bool, empty: Bool) {
        self.name = name; self.level = level; self.low = low; self.empty = empty
    }
}

/// The answer ("2 low"), its tone, one line under it, and every battery lowest-first.
public struct BatterySummary: Sendable, Equatable {
    public let headline: String; public let tone: DoorsTone; public let detail: String?; public let rows: [BatteryRow]
    public init(headline: String, tone: DoorsTone, detail: String?, rows: [BatteryRow]) {
        self.headline = headline; self.tone = tone; self.detail = detail; self.rows = rows
    }
}

/// "Living Area Motion Sensor Battery" → "Living Area Motion Sensor";
/// "Temperature Humidity Sensor: Master Bedroom Battery" → "Master Bedroom sensor".
func cleanBatteryName(_ raw: String) -> String {
    let name = raw.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "(?i)\\s+battery( level)?$", with: "", options: .regularExpression)
    guard let colon = name.range(of: ": ") else { return name }
    let before = String(name[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
    let what = (before.split(separator: " ").last.map(String.init) ?? "").lowercased()
    let after = String(name[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
    return "\(after) \(what)"
}

/// Parse `BATTERY_TEMPLATE`'s reply; empty if it isn't one.
public func batteriesFromTemplate(_ json: String?) -> [Battery] {
    guard let json, let data = json.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    return arr.compactMap { o in
        guard let id = o["id"] as? String else { return nil }
        guard let lvl = (o["level"] as? Double) ?? (o["level"] as? Int).map(Double.init) else { return nil }
        let rawName = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        return Battery(id: id, name: cleanBatteryName(rawName), level: Swift.min(100, Swift.max(0, Int(lvl.rounded()))))
    }
}

public func batterySummary(_ list: [Battery]) -> BatterySummary {
    let rows = list.sorted { ($0.level, $0.name) < ($1.level, $1.name) }
        .map { BatteryRow(name: $0.name, level: $0.level, low: $0.level <= BATTERY_LOW, empty: $0.level <= BATTERY_EMPTY) }
    guard let first = rows.first else {
        return BatterySummary(headline: "No batteries found", tone: .unknown, detail: nil, rows: rows)
    }
    let low = rows.filter { $0.low }
    let tone: DoorsTone = low.contains { $0.empty } ? .alert : (low.isEmpty ? .calm : .warn)
    return BatterySummary(
        headline: low.isEmpty ? "All good" : "\(low.count) low",
        tone: tone,
        detail: low.isEmpty ? "Lowest: \(first.name) \(first.level)%" : low.map { "\($0.name) \($0.level)%" }.joined(separator: ", "),
        rows: rows)
}
