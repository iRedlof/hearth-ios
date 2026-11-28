import Foundation
import CoreFoundation

/// Builds the structural, secret-free description of why a ChargePoint reply could not be parsed.
/// It names the key path and the expected-versus-found type, or classifies the body as "empty body",
/// "not JSON" or "HTML page" with a byte length. It NEVER returns a value from the response (no id,
/// token, cookie, email, name or status string) — only JSON type names, key paths and a byte count.
/// Deterministic and pure so it is safe to log and to show in Diagnostics.
public func cpParseFaultDetail(request: CpParseRequest, body: String) -> String {
    let bytes = body.utf8.count
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "empty body" }
    let lowered = trimmed.lowercased()
    if trimmed.first == "<" || lowered.hasPrefix("<!doctype") || lowered.contains("<html") {
        return "HTML page (\(bytes) bytes)"
    }
    guard let any = try? JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed]) else {
        return "not JSON (\(bytes) bytes)"
    }
    guard let root = any as? [String: Any] else {
        return "top-level \(cpJSONTypeName(any)), expected object"
    }
    switch request {
    case .status: return cpStatusFaultDetail(root) ?? "status: unrecognized shape"
    case .stationList: return cpStationsFaultDetail(root) ?? "station list: unrecognized shape"
    }
}

/// A JSON value's type name for diagnostics. Distinguishes a boolean from a number and reports an
/// absent key, so a reader can tell "found string" from "absent". Never the value itself.
func cpJSONTypeName(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return value is NSNull ? "null" : "absent" }
    if let number = value as? NSNumber {
        return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
    }
    if value is String { return "string" }
    if value is [Any] { return "array" }
    if value is [String: Any] { return "object" }
    return "unknown"
}

/// Mirrors the required shape in `cpOwnedObservation` for the user-status read, returning the first
/// structural mismatch it finds (or nil if the top-level shape looks acceptable).
private func cpStatusFaultDetail(_ root: [String: Any]) -> String? {
    if root["error"] != nil || root["error_message"] != nil { return "root: provider error present" }
    guard let user = root["user_status"] as? [String: Any] else {
        return "user_status: expected object, \(cpJSONTypeName(root["user_status"]))"
    }
    if user["error"] != nil || user["error_message"] != nil { return "user_status: provider error present" }
    if let rawCharging = user["charging"] {
        guard let charging = rawCharging as? [String: Any] else {
            return "user_status.charging: expected object, \(cpJSONTypeName(rawCharging))"
        }
        guard let state = charging["state"] as? String, !state.isEmpty else {
            return "user_status.charging.state: expected non-empty string, \(cpJSONTypeName(charging["state"]))"
        }
        if !cpSessionDone.contains(state.lowercased()), cpOwnedInteger(charging["sessionId"]) == nil {
            return "user_status.charging.sessionId: expected integer, \(cpJSONTypeName(charging["sessionId"]))"
        }
    }
    if let rawWaitlist = user["waitlist"] {
        guard let waitlist = rawWaitlist as? [String: Any] else {
            return "user_status.waitlist: expected object, \(cpJSONTypeName(rawWaitlist))"
        }
        if let rawState = waitlist["state"] {
            if let text = rawState as? String {
                if text != "NOT_QUEUED" { return "user_status.waitlist.state: expected object or \"NOT_QUEUED\", string" }
            } else if let state = rawState as? [String: Any] {
                if let token = state["token"], !(token is String) {
                    return "user_status.waitlist.state.token: expected string, \(cpJSONTypeName(token))"
                }
                for key in ["deviceId", "portNo"] where state[key] != nil && cpOwnedInteger(state[key]) == nil {
                    return "user_status.waitlist.state.\(key): expected integer, \(cpJSONTypeName(state[key]))"
                }
            } else {
                return "user_status.waitlist.state: expected object or string, \(cpJSONTypeName(rawState))"
            }
        }
        if let rawStations = waitlist["stations"], !(rawStations is [Any]) {
            return "user_status.waitlist.stations: expected array, \(cpJSONTypeName(rawStations))"
        }
    }
    return nil
}

/// Mirrors the required shape in `cpOwnedStations` for the map read.
private func cpStationsFaultDetail(_ root: [String: Any]) -> String? {
    if root["error"] != nil || root["error_message"] != nil { return "root: provider error present" }
    guard let map = root["map_data"] as? [String: Any] else {
        return "map_data: expected object, \(cpJSONTypeName(root["map_data"]))"
    }
    if map["error"] != nil || map["error_message"] != nil { return "map_data: provider error present" }
    guard let stations = map["stations"] as? [[String: Any]] else {
        return "map_data.stations: expected array of objects, \(cpJSONTypeName(map["stations"]))"
    }
    for (index, station) in stations.enumerated() {
        if cpOwnedInteger(station["device_id"]) == nil {
            return "map_data.stations[\(index)].device_id: expected integer, \(cpJSONTypeName(station["device_id"]))"
        }
        for key in ["lat", "lon"] where !(station[key] is NSNumber) || station[key] is Bool {
            return "map_data.stations[\(index)].\(key): expected number, \(cpJSONTypeName(station[key]))"
        }
    }
    return nil
}
