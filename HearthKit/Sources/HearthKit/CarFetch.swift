import Foundation

/// One successful template response and the last response from this vehicle with a battery reading.
/// Keeping these together prevents a refresh from mixing a new timestamp with old telemetry.
public struct CarReadingsCache: Sendable, Equatable, Codable {
    public let current: String
    public let lastGood: String?
    public let checkedAt: Date
    public let lastGoodCheckedAt: Date?

    public init(current: String, lastGood: String?, checkedAt: Date, lastGoodCheckedAt: Date? = nil) {
        self.current = current; self.lastGood = lastGood; self.checkedAt = checkedAt
        self.lastGoodCheckedAt = lastGoodCheckedAt
    }

    /// Legacy records can prove a historical time only when the two raw responses are identical.
    public var historicalObservedAt: Date? {
        lastGoodCheckedAt ?? (lastGood != nil && lastGood == current ? checkedAt : nil)
    }
}

private struct CarReplyShape: Decodable {
    let found: Bool
    let prefix: String?
    let s: [String: String]?

    private enum CodingKeys: String, CodingKey { case found, prefix, s }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        found = try values.decode(Bool.self, forKey: .found)
        prefix = (try? values.decode(String.self, forKey: .prefix))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s = try values.decodeIfPresent([String: String].self, forKey: .s)
    }
}

private func carReply(_ json: String) throws -> CarReplyShape {
    guard let data = json.data(using: .utf8),
          let reply = try? JSONDecoder().decode(CarReplyShape.self, from: data),
          !reply.found || reply.s != nil else { throw HaError("Couldn't read car data") }
    return reply
}

/// Vehicle attribution comes only from a valid current template response, never its display name.
public struct CarReplyIdentity: Sendable, Equatable {
    public let found: Bool
    public let vehiclePrefix: String?
}

public func carReplyIdentity(_ json: String?) -> CarReplyIdentity? {
    guard let json, let reply = try? carReply(json) else { return nil }
    let prefix = reply.prefix.flatMap { carUnknownStates.contains($0.lowercased()) ? nil : $0 }
    return CarReplyIdentity(found: reply.found, vehiclePrefix: reply.found ? prefix : nil)
}

/// Apply a successful response to the latest cache. Call again after suspension when app and
/// extension refreshes overlap, so an unknown reading cannot replace a newer last-good response.
public func carReadingsAfterReply(_ json: String, previous: CarReadingsCache?, checkedAt: Date) throws -> CarReadingsCache {
    _ = try carReply(json)
    guard let identity = carReplyIdentity(json) else { throw HaError("Couldn't read car data") }
    let sameVehicle = identity.vehiclePrefix != nil &&
        identity.vehiclePrefix == carReplyIdentity(previous?.current)?.vehiclePrefix &&
        identity.vehiclePrefix == carReplyIdentity(previous?.lastGood)?.vehiclePrefix
    let freshGood = carFromTemplate(json)?.battery != nil && identity.vehiclePrefix != nil
    let lastGood: String? = freshGood ? json
        : (identity.found && sameVehicle ? previous?.lastGood : nil)
    return CarReadingsCache(current: json, lastGood: lastGood, checkedAt: checkedAt,
        lastGoodCheckedAt: freshGood ? checkedAt : (lastGood != nil ? previous?.historicalObservedAt : nil))
}

public struct CarFetchResult: Sendable, Equatable {
    public let cache: CarReadingsCache?
    public let error: String?
    public let setup: Bool

    public init(cache: CarReadingsCache?, error: String? = nil, setup: Bool = false) {
        self.cache = cache; self.error = error; self.setup = setup
    }

    public var currentCar: Car? { carFromTemplate(cache?.current) }

    public var shownCar: CarShown? {
        let prefix = carReplyIdentity(cache?.current)?.vehiclePrefix
        let sameVehicle = prefix != nil && prefix == carReplyIdentity(cache?.lastGood)?.vehiclePrefix
        return carToShow(currentCar, sameVehicle ? carFromTemplate(cache?.lastGood) : nil)
    }

    public var displayedObservedAt: Date? {
        guard let shown = shownCar else { return nil }
        return shown.stale ? cache?.historicalObservedAt : cache?.checkedAt
    }

    public func snapshot(now: Date = .now, zone: TimeZone = .current,
                         locale: Locale = .current) -> CarSnapshot {
        let shown = shownCar
        var value = carSnapshot(shown?.car, now: now,
            stale: error != nil || shown?.stale == true, checkedAt: cache?.checkedAt,
            zone: zone, locale: locale)
        if setup {
            value.needsSettings = true
            value.place = "Connect in Settings"
            value.chargeLine = "Set up Home Assistant"
        } else if let error {
            value.error = error
            value.needsSettings = beaconNeedsSettings(error)
            value.needsSignIn = beaconNeedsSignIn(error)
            value.chargeLine = error.contains("Can't reach") ? "Can't connect"
                : value.needsSignIn ? "Sign in again"
                : value.needsSettings ? "Check setup" : "Check failed"
            if shown == nil { value.place = "No readings available" }
        }
        return value
    }
}

/// Refreshes cached readings without waking the car. A valid no-car response is a success;
/// malformed data and network errors preserve the previous successful response and check time.
public func fetchCarReadings(_ config: HaConfig?, previous: CarReadingsCache? = nil,
                             now: Date = .now,
                             request: (@Sendable () async throws -> String)? = nil) async -> CarFetchResult {
    guard let config, config.carReady else { return CarFetchResult(cache: nil, setup: true) }
    do {
        let json: String
        if let request { json = try await request() }
        else { json = try await HaClient(config).template(CAR_TEMPLATE) }
        return CarFetchResult(cache: try carReadingsAfterReply(json, previous: previous, checkedAt: now))
    } catch is CancellationError {
        return CarFetchResult(cache: previous, error: "Refresh interrupted")
    } catch {
        return CarFetchResult(cache: previous, error: friendlyError(error))
    }
}
