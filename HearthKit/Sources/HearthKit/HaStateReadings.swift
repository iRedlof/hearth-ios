import Foundation

public enum HaReadingFailureReason: String, Codable, Sendable, Equatable {
    case authentication, entityNotFound, transport, interrupted, malformed, other
}

/// Successful state replies travel with their entity and check time as one cache record.
public struct HaStateReading: Sendable, Equatable, Codable {
    public let entityID: String
    public let json: String
    public let checkedAt: Date
    public init(entityID: String, json: String, checkedAt: Date) {
        self.entityID = entityID; self.json = json; self.checkedAt = checkedAt
    }
}

public struct HaReadingsResult: Sendable {
    public let readings: [String: HaStateReading]
    public let errors: [String: String]
    public let failureReasons: [String: HaReadingFailureReason]
}

/// Parallel selected-entity reads. Errors retain only that entity's successful reply; successful
/// unknown/unavailable states remain explicit readings rather than borrowing older live status.
public func fetchHaStateReadings(_ config: HaConfig, ids: [String],
                                previous: [String: HaStateReading] = [:], now: Date = .now,
                                request: (@Sendable (String) async throws -> String)? = nil) async -> HaReadingsResult {
    var seen = Set<String>()
    let ordered = ids.filter { seen.insert($0).inserted }
    return await withTaskGroup(of: (String, HaStateReading?, String?, HaReadingFailureReason?).self) { group in
        for id in ordered {
            group.addTask {
                do {
                    try Task.checkCancellation()
                    let json: String
                    if let request { json = try await request(id) }
                    else { json = try await HaClient(config).stateJson(id) }
                    try Task.checkCancellation()
                    guard let data = json.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let state = obj["state"] as? String, !state.isEmpty,
                          obj["entity_id"] == nil || obj["entity_id"] as? String == id else {
                        let old = previous[id].flatMap { $0.entityID == id ? $0 : nil }
                        return (id, old, "Couldn't read \(id.split(separator: ".").first ?? "entity") data", .malformed)
                    }
                    return (id, HaStateReading(entityID: id, json: json, checkedAt: now), nil, nil)
                } catch {
                    let old = previous[id].flatMap { $0.entityID == id ? $0 : nil }
                    let message = error is CancellationError ? "Refresh interrupted" : friendlyError(error)
                    let reason: HaReadingFailureReason
                    if error is CancellationError { reason = .interrupted }
                    else if let error = error as? HaError, error.code == 401 { reason = .authentication }
                    else if let error = error as? HaError, error.code == 404 { reason = .entityNotFound }
                    else if error is URLError { reason = .transport }
                    else { reason = .other }
                    return (id, old, message, reason)
                }
            }
        }
        var readings: [String: HaStateReading] = [:], errors: [String: String] = [:]
        var reasons: [String: HaReadingFailureReason] = [:]
        for await (id, reading, error, reason) in group {
            readings[id] = reading; errors[id] = error
            reasons[id] = reason
        }
        return HaReadingsResult(readings: readings, errors: errors, failureReasons: reasons)
    }
}
