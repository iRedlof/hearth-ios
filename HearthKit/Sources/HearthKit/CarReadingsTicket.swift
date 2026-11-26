import Foundation

/// Only this ticket's UUID travels through a widget intent. The complete reading stays in the
/// protected App Group, without the HA connection configuration or credentials.
public struct CarReadingsTicket: Codable, Sendable, Equatable, Identifiable {
    public static let maximumLifetime: TimeInterval = 48 * 60 * 60
    public let version: Int
    public let id: UUID
    public let entryID: UUID
    public let issuedAt: Date
    public let expiresAt: Date
    public let origin: CarReadingOrigin
    public let cache: CarReadingsCache?
    public let error: String?
    public let setup: Bool
    public let reply: CarTicketReply?

    public init(envelope: CarLiveEnvelope, entryID: UUID = UUID(), id: UUID = UUID(),
                issuedAt: Date = .now, lifetime: TimeInterval = 48 * 60 * 60) throws {
        guard lifetime.isFinite, lifetime > 0, lifetime <= Self.maximumLifetime,
              issuedAt.timeIntervalSince1970.isFinite else {
            throw CarReadingsTicketError.invalid
        }
        version = 1; self.id = id; self.entryID = entryID
        self.issuedAt = issuedAt; expiresAt = issuedAt.addingTimeInterval(lifetime)
        origin = envelope.origin; cache = envelope.result.cache
        error = envelope.result.error; setup = envelope.result.setup
        reply = envelope.requestReply.map {
            switch $0 {
            case .success(let raw): .success(raw: raw)
            case .failure(let failure): .failure(message: failure.message, code: failure.code)
            }
        }
        guard coherent else { throw CarReadingsTicketError.invalid }
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, entryID, issuedAt, expiresAt, origin, cache, error, setup, reply
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        version = try fields.decode(Int.self, forKey: .version)
        id = try fields.decode(UUID.self, forKey: .id)
        entryID = try fields.decode(UUID.self, forKey: .entryID)
        issuedAt = try fields.decode(Date.self, forKey: .issuedAt)
        expiresAt = try fields.decode(Date.self, forKey: .expiresAt)
        origin = try fields.decode(CarReadingOrigin.self, forKey: .origin)
        cache = try fields.decodeIfPresent(CarReadingsCache.self, forKey: .cache)
        error = try fields.decodeIfPresent(String.self, forKey: .error)
        setup = try fields.decode(Bool.self, forKey: .setup)
        reply = try fields.decodeIfPresent(CarTicketReply.self, forKey: .reply)
        guard coherent else { throw CarReadingsTicketError.invalid }
    }

    private var coherent: Bool {
        let lifetime = expiresAt.timeIntervalSince(issuedAt)
        guard version == 1, issuedAt.timeIntervalSince1970.isFinite,
              expiresAt.timeIntervalSince1970.isFinite, lifetime > 0,
              lifetime <= Self.maximumLifetime, origin.attemptedAt.timeIntervalSince1970.isFinite,
              origin.observedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              origin.displayedObservedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { return false }
        if origin.configReady {
            guard origin.requestScope?.isEmpty == false, origin.readRevision == origin.requestScope else { return false }
        }
        guard let cache else { return origin.observedAt == nil && origin.displayedObservedAt == nil }
        guard let identity = carReplyIdentity(cache.current),
              identity.vehiclePrefix == origin.vehiclePrefix,
              cache.checkedAt == origin.observedAt else { return false }
        if let historical = cache.lastGood {
            guard identity.vehiclePrefix != nil,
                  carReplyIdentity(historical)?.vehiclePrefix == identity.vehiclePrefix,
                  cache.lastGoodCheckedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else {
                return false
            }
        } else if cache.lastGoodCheckedAt != nil { return false }
        // The snapshot's whole-car fallback selects the displayed cohort. An arbitrary current
        // or historical time is insufficient: it must describe the cohort the entry actually showed.
        return origin.displayedObservedAt ==
            CarFetchResult(cache: cache, error: error, setup: setup).displayedObservedAt
    }

    /// `.current` validates route identity, not telemetry freshness or command authorization.
    public func validation(in context: HaStoreSnapshot?, now: Date = .now) -> CarReadingsRouteStatus {
        guard coherent, now.timeIntervalSince1970.isFinite else { return .unavailable }
        guard now < expiresAt else { return .expired }
        guard origin.status != .storageUnavailable else { return .storageUnavailable }
        guard origin.status != .obsolete else { return .superseded }
        guard let context else { return .storageUnavailable }
        guard context.scope == origin.requestScope else { return .configurationChanged }
        guard let prefix = origin.vehiclePrefix, origin.configReady else { return .explanationOnly }
        guard context.config?.carReady == true else { return .configurationChanged }
        guard normalizedCarVehiclePrefix(prefix) == prefix,
              let stored = context.collectionCaches["car"], let payload = stored.payload,
              let current = try? JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8)),
              stored.observedAt == current.checkedAt,
              let currentPrefix = carReplyIdentity(current.current)?.vehiclePrefix else { return .targetUnavailable }
        guard prefix == currentPrefix else { return .configurationChanged }
        return .current
    }
}

public enum CarTicketReply: Codable, Sendable, Equatable {
    case success(raw: String)
    case failure(message: String, code: Int)
}

public enum CarReadingsRouteStatus: String, Codable, Sendable {
    case current, explanationOnly, configurationChanged, targetUnavailable, storageUnavailable
    case expired, unavailable, superseded
}

public enum CarReadingsTicketError: Error, Sendable {
    case invalid, oversized, duplicate
}
