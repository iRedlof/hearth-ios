import Foundation
import CoreFoundation

/// Every replaceable percentage or binary battery sensor, excluding self-charging integrations (phones,
/// the car, vacuum, powerwall). Ported verbatim from Android `BatteryState.kt`.
public let BATTERY_TEMPLATE = """
{%- set ns = namespace(skip=[], l=[]) -%}
{%- for i in ['mobile_app', 'tesla_custom', 'tesla_fleet', 'teslemetry', 'tessie', 'roborock', 'tesla_wall_connector', 'powerwall'] -%}{%- set ns.skip = ns.skip + integration_entities(i) -%}{%- endfor -%}
{%- for s in states.sensor if s.attributes.device_class == 'battery' and s.attributes.unit_of_measurement == '%' and s.entity_id not in ns.skip -%}
{%- set ns.l = ns.l + [{'id': s.entity_id, 'name': s.name, 'kind': 'numeric', 'state': s.state, 'level': s.state}] -%}
{%- endfor -%}
{%- for s in states.binary_sensor if s.attributes.device_class == 'battery' and s.entity_id not in ns.skip -%}
{%- set ns.l = ns.l + [{'id': s.entity_id, 'name': s.name, 'kind': 'binary', 'state': s.state}] -%}
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

public enum BatteryKind: String, Sendable, Equatable { case numeric, binary }

public struct Battery: Sendable, Equatable {
    public let id: String; public let name: String; public let level: Int?
    public let kind: BatteryKind; public let binaryLow: Bool?; public let state: String?; public let rawLevel: Double?
    public init(id: String, name: String, level: Int?, kind: BatteryKind = .numeric,
                binaryLow: Bool? = nil, state: String? = nil, rawLevel: Double? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.state = state
        let known = state != "unknown" && state != "unavailable"
        self.binaryLow = kind == .binary && known ? binaryLow : nil
        let validated = known ? validatedBatteryPercent(rawLevel ?? level.map(Double.init)) : nil
        self.rawLevel = kind == .numeric ? validated : nil
        self.level = kind == .numeric ? validated.map { Int($0.rounded()) } : nil
    }
}

public struct BatteryRow: Sendable, Equatable {
    public let name: String; public let level: Int?; public let low: Bool; public let empty: Bool
    public let id: String; public let kind: BatteryKind; public let binaryLow: Bool?; public let state: String?; public let rawLevel: Double?
    public init(name: String, level: Int?, low: Bool, empty: Bool, id: String? = nil,
                kind: BatteryKind = .numeric, binaryLow: Bool? = nil, state: String? = nil, rawLevel: Double? = nil) {
        self.name = name; self.level = level; self.low = low; self.empty = empty
        self.id = id ?? name; self.kind = kind; self.binaryLow = binaryLow; self.state = state
        self.rawLevel = kind == .numeric ? validatedBatteryPercent(rawLevel ?? level.map(Double.init)) : nil
    }
    public var available: Bool {
        state != "unknown" && state != "unavailable" && (kind == .binary ? binaryLow != nil : level != nil)
    }
    public var readingLabel: String {
        guard available else { return "Unavailable" }
        if kind == .binary { return binaryLow == true ? "Low" : "OK" }
        return "\(level!)%"
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

/// Validate before integer conversion, including Foundation's boolean NSNumber bridge.
public func validatedBatteryPercent(_ value: Any?) -> Double? {
    let number: Double?
    if let value = value as? NSNumber {
        guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        number = value.doubleValue
    } else if let value = value as? String {
        number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    } else { number = nil }
    guard let number, number.isFinite, (0...100).contains(number) else { return nil }
    return number
}

/// Strict envelope: structural corruption or duplicate IDs fail the entire response.
/// Invalid measurements remain represented as unavailable.
public func parseBatteryCollection(_ json: String, cleanNames: Bool = true) throws -> [Battery] {
    guard let data = json.data(using: .utf8),
          let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw HaError("Unexpected batteries reading")
    }
    var ids = Set<String>()
    return try array.map { row in
        guard let id = row["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ids.insert(id).inserted else { throw HaError("Missing or duplicate battery identity") }
        for field in ["name", "state"] {
            if let value = row[field], !(value is NSNull), !(value is String) {
                throw HaError("Unexpected battery \(field)")
            }
        }
        let kind: BatteryKind
        if let value = row["kind"], !(value is NSNull) {
            guard let text = value as? String, let parsed = BatteryKind(rawValue: text) else {
                throw HaError("Unexpected battery kind")
            }
            kind = parsed
        } else { kind = id.hasPrefix("binary_sensor.") ? .binary : .numeric }
        let name = (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        let state = row["state"] as? String
        let unavailable = state == "unknown" || state == "unavailable"
        let rawLevel = kind == .numeric && !unavailable
            ? validatedBatteryPercent(row.keys.contains("rawLevel") ? row["rawLevel"] : row["level"]) : nil
        let binaryLow: Bool?
        if kind == .binary && !unavailable {
            switch state {
            case "on": binaryLow = true
            case "off": binaryLow = false
            case nil:
                if let value = row["binaryLow"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() {
                    binaryLow = value.boolValue
                } else { binaryLow = nil }
            default: binaryLow = nil
            }
        } else { binaryLow = nil }
        return Battery(id: id, name: cleanNames ? cleanBatteryName(name) : name,
                       level: rawLevel.map { Int($0.rounded()) }, kind: kind,
                       binaryLow: binaryLow, state: state, rawLevel: rawLevel)
    }
}

/// Compatibility adapter; fetch mapping uses the strict parser to distinguish malformed from [].
public func batteriesFromTemplate(_ json: String?) -> [Battery] {
    guard let json else { return [] }
    return (try? parseBatteryCollection(json)) ?? []
}

public func batteriesToJson(_ batteries: [Battery]) -> String {
    let array: [[String: Any]] = batteries.map {
        ["id": $0.id, "name": $0.name, "level": $0.level.map { $0 as Any } ?? NSNull(),
         "rawLevel": $0.rawLevel.map { $0 as Any } ?? NSNull(), "kind": $0.kind.rawValue,
         "binaryLow": $0.binaryLow.map { $0 as Any } ?? NSNull(), "state": $0.state.map { $0 as Any } ?? NSNull()]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: array), let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}

public func batteriesFromJson(_ json: String?) -> [Battery] {
    guard let json else { return [] }
    return (try? parseBatteryCollection(json, cleanNames: false)) ?? []
}

public func batterySummary(_ list: [Battery]) -> BatterySummary {
    let rows = list.map { battery in
        let raw = validatedBatteryPercent(battery.rawLevel)
        let numeric = battery.kind == .numeric
        return BatteryRow(name: battery.name, level: numeric ? raw.map { Int($0.rounded()) } : nil,
                          low: numeric ? raw.map { $0 <= Double(BATTERY_LOW) } ?? false : battery.binaryLow == true,
                          empty: numeric && raw.map { $0 <= Double(BATTERY_EMPTY) } == true,
                          id: battery.id, kind: battery.kind, binaryLow: numeric ? nil : battery.binaryLow,
                          state: battery.state, rawLevel: numeric ? raw : nil)
    }.sorted {
        let left = ($0.low ? 0 : ($0.available ? 2 : 1), $0.rawLevel ?? ($0.low ? Double(BATTERY_LOW) : 101), $0.name, $0.id)
        let right = ($1.low ? 0 : ($1.available ? 2 : 1), $1.rawLevel ?? ($1.low ? Double(BATTERY_LOW) : 101), $1.name, $1.id)
        return left < right
    }
    guard !rows.isEmpty else {
        return BatterySummary(headline: "No batteries found", tone: .unknown, detail: nil, rows: rows)
    }
    let low = rows.filter { $0.low }
    let unavailable = rows.filter { !$0.available }.count
    let tone: DoorsTone = low.contains { $0.empty } ? .alert : (!low.isEmpty ? .warn : (unavailable > 0 ? .unknown : .calm))
    let detail: String
    if !low.isEmpty {
        detail = low.map { "\($0.name) \($0.readingLabel)" }.joined(separator: ", ") +
            (unavailable > 0 ? " · \(unavailable) unavailable" : "")
    } else if unavailable > 0 { detail = "Some batteries have no current reading" }
    else if let first = rows.first(where: { $0.level != nil }) { detail = "Lowest: \(first.name) \(first.readingLabel)" }
    else { detail = "All batteries OK" }
    return BatterySummary(
        headline: !low.isEmpty ? "\(low.count) low" : (unavailable > 0 ? "\(unavailable) unavailable" : "All good"),
        tone: tone,
        detail: detail,
        rows: rows)
}
