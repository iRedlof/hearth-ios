import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A coherent connection and its successful entity readings, shared by app and widget processes.
public struct HaStateFailure: Codable, Sendable, Equatable {
    public let message: String
    public let checkedAt: Date
}

/// A failed attempt preserves the successful payload and its original observation time.
public struct HaCollectionCache: Codable, Sendable, Equatable {
    public let payload: String?
    public let observedAt: Date?
    public let error: String?
    public let attemptedAt: Date
}

public struct HaCollectionReadOwner: Sendable, Equatable {
    public let kind: String
    public let scope: String
    public let revision: String
    public let readID: String
    public init(kind: String, scope: String, revision: String, readID: String) {
        self.kind = kind; self.scope = scope; self.revision = revision; self.readID = readID
    }
}

/// A read-only Car route owns both the connection generation and one validated integration prefix.
/// It is deliberately separate from discovery, whose reply is allowed to choose a new vehicle.
public struct HaCarRouteReadOwner: Sendable, Equatable {
    public let scope: String
    public let vehiclePrefix: String
    public let readID: String
    public init(scope: String, vehiclePrefix: String, readID: String) {
        self.scope = scope; self.vehiclePrefix = vehiclePrefix; self.readID = readID
    }
}

public struct HaStoreSnapshot: Sendable {
    public let config: HaConfig?
    public let scope: String
    public let readings: [String: HaStateReading]
    public let climateRevision: String
    public let climateOperation: ClimateOperation?
    public let alarmRevision: String
    public let alarmOperation: AlarmOperation?
    public let failures: [String: HaStateFailure]
    public let collectionRevision: String
    public let collectionCaches: [String: HaCollectionCache]
    public let doorOperation: DoorOperation?
    public let doorActionRevision: String

    /// Also permits an in-memory Settings runtime to supply a coherent, empty-cache context.
    public init(config: HaConfig?, scope: String, readings: [String: HaStateReading] = [:],
                climateRevision: String = "initial", climateOperation: ClimateOperation? = nil,
                alarmRevision: String = "initial", alarmOperation: AlarmOperation? = nil,
                failures: [String: HaStateFailure] = [:], collectionRevision: String = "initial",
                collectionCaches: [String: HaCollectionCache] = [:], doorOperation: DoorOperation? = nil,
                doorActionRevision: String = "initial") {
        self.config = config; self.scope = scope; self.readings = readings
        self.climateRevision = climateRevision; self.climateOperation = climateOperation
        self.alarmRevision = alarmRevision; self.alarmOperation = alarmOperation
        self.failures = failures; self.collectionRevision = collectionRevision
        self.collectionCaches = collectionCaches; self.doorOperation = doorOperation
        self.doorActionRevision = doorActionRevision
    }
}

/// All readers and writers lock a permanent sidecar. The JSON file may then be replaced atomically
/// without changing the inode on which another process is waiting.
public struct HaStateStore: Sendable {
    private let directory: URL
    private let initialConfig: HaConfig?
    private let initialScope: String
    private static let carReadLeaseDuration: TimeInterval = 60
    private struct CarReadLease: Codable {
        // Missing legacy metadata is abandoned ownership; unreadable field types remain corruption.
        var readID: String?
        var startedAt: Date?
        var expiresAt: Date?

        func isActive(readID: String, now: Date) -> Bool {
            guard !readID.isEmpty, self.readID == readID,
                  let startedAt, let expiresAt,
                  startedAt.timeIntervalSinceReferenceDate.isFinite,
                  expiresAt.timeIntervalSinceReferenceDate.isFinite,
                  expiresAt.timeIntervalSince(startedAt) == HaStateStore.carReadLeaseDuration else { return false }
            return startedAt <= now && now < expiresAt
        }
    }
    private struct Stored: Codable {
        var version = 1
        var config: HaConfig?
        var scope: String
        var readings: [String: HaStateReading]
        var climateRevision: String
        var climateOperation: ClimateOperation?
        var alarmRevision: String
        var alarmOperation: AlarmOperation?
        var failures: [String: HaStateFailure]
        var collectionRevision: String
        var collectionCaches: [String: HaCollectionCache]
        var collectionReads: [String: String]
        var carRouteReadPrefix: String?
        var carReadLease: CarReadLease?
        var doorOperation: DoorOperation?
        var doorActionRevision: String
        init(config: HaConfig?, scope: String, readings: [String: HaStateReading],
             climateRevision: String = UUID().uuidString, climateOperation: ClimateOperation? = nil,
             alarmRevision: String = UUID().uuidString, alarmOperation: AlarmOperation? = nil,
             failures: [String: HaStateFailure] = [:],
             collectionRevision: String = UUID().uuidString, collectionCaches: [String: HaCollectionCache] = [:],
             collectionReads: [String: String] = [:], carRouteReadPrefix: String? = nil, doorOperation: DoorOperation? = nil,
             doorActionRevision: String = UUID().uuidString) {
            self.config = config; self.scope = scope; self.readings = readings
            self.climateRevision = climateRevision; self.climateOperation = climateOperation
            self.alarmRevision = alarmRevision; self.alarmOperation = alarmOperation
            self.failures = failures
            self.collectionRevision = collectionRevision; self.collectionCaches = collectionCaches
            self.collectionReads = collectionReads
            self.carRouteReadPrefix = carRouteReadPrefix
            self.carReadLease = nil
            self.doorOperation = doorOperation
            self.doorActionRevision = doorActionRevision
        }
        private enum CodingKeys: String, CodingKey {
            case version, config, scope, readings, climateRevision, climateOperation, alarmRevision, alarmOperation, failures
            case collectionRevision, collectionCaches, collectionReads, carRouteReadPrefix, carReadLease, doorOperation, doorActionRevision
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            config = try values.decodeIfPresent(HaConfig.self, forKey: .config)
            scope = try values.decode(String.self, forKey: .scope)
            readings = try values.decode([String: HaStateReading].self, forKey: .readings)
            climateRevision = try values.decodeIfPresent(String.self, forKey: .climateRevision) ?? "legacy"
            climateOperation = try values.decodeIfPresent(ClimateOperation.self, forKey: .climateOperation)
            alarmRevision = try values.decodeIfPresent(String.self, forKey: .alarmRevision) ?? "legacy"
            alarmOperation = try values.decodeIfPresent(AlarmOperation.self, forKey: .alarmOperation)
            failures = try values.decodeIfPresent([String: HaStateFailure].self, forKey: .failures) ?? [:]
            collectionRevision = try values.decodeIfPresent(String.self, forKey: .collectionRevision) ?? "legacy"
            collectionCaches = try values.decodeIfPresent([String: HaCollectionCache].self, forKey: .collectionCaches) ?? [:]
            collectionReads = try values.decodeIfPresent([String: String].self, forKey: .collectionReads) ?? [:]
            carRouteReadPrefix = try values.decodeIfPresent(String.self, forKey: .carRouteReadPrefix)
            carReadLease = try values.decodeIfPresent(CarReadLease.self, forKey: .carReadLease)
            doorOperation = try values.decodeIfPresent(DoorOperation.self, forKey: .doorOperation)
            // A deterministic legacy value remains stable across processes and is persisted on the next mutation.
            // Old collection-revision callbacks do not accidentally become fresh command origins.
            doorActionRevision = try values.decodeIfPresent(String.self, forKey: .doorActionRevision)
                ?? "door-action-legacy:\(scope):\(collectionRevision)"
            guard !doorActionRevision.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        }
        var snapshot: HaStoreSnapshot {
            HaStoreSnapshot(config: config, scope: scope, readings: readings,
                climateRevision: climateRevision, climateOperation: climateOperation,
                alarmRevision: alarmRevision, alarmOperation: alarmOperation, failures: failures,
                collectionRevision: collectionRevision, collectionCaches: collectionCaches, doorOperation: doorOperation,
                doorActionRevision: doorActionRevision)
        }
    }

    public init(directory: URL, initialConfig: HaConfig? = nil, initialScope: String = "initial") {
        self.directory = directory; self.initialConfig = initialConfig; self.initialScope = initialScope
    }

    public func snapshot() throws -> HaStoreSnapshot {
        try locked { try read().snapshot }
    }

    public func doorServiceGate(entityID: String) -> HaDoorServiceGate {
        HaDoorServiceGate(directory: directory, entityID: entityID)
    }

    /// Network and discovery failures settle only their captured read, exactly like successful replies.
    public func failCollectionRead(_ owner: HaCollectionReadOwner, error: String, now: Date) throws -> HaStoreSnapshot? {
        try mergeCollection(owner.kind, reply: .failure(HaError(error)), expectedScope: owner.scope,
            expectedRevision: owner.revision, readID: owner.readID, now: now)
    }

    /// Apply a Settings field edit to the current account record, preserving concurrent discovery.
    public func editConfig(expectedScope: String, edit: (inout HaConfig) -> Void) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, var config = stored.config else { return nil }
            edit(&config)
            applyConfig(config, to: &stored)
            try write(stored)
            return stored.snapshot
        }
    }

    /// Account changes rotate the persisted generation even when signing back into the same account.
    /// Picker edits preserve the account scope and independently cached entity readings.
    @discardableResult public func saveConfig(_ config: HaConfig?) throws -> HaStoreSnapshot {
        try locked {
            var stored = try read()
            applyConfig(config, to: &stored)
            try write(stored)
            return stored.snapshot
        }
    }

    private func applyConfig(_ config: HaConfig?, to stored: inout Stored) {
        let connectionChanged = config == nil || !haSameConnection(stored.config, config)
        if connectionChanged {
            stored.scope = UUID().uuidString
            stored.readings = [:]
            stored.failures = [:]
        }
        if stored.config?.climateId != config?.climateId || stored.config?.resumeId != config?.resumeId
            || config == nil || !haSameConnection(stored.config, config) {
            stored.climateRevision = UUID().uuidString
            stored.climateOperation = nil
        }
        if stored.config?.entityId != config?.entityId || stored.config?.lockId != config?.lockId
            || config == nil || !haSameConnection(stored.config, config) {
            stored.alarmRevision = UUID().uuidString
            stored.alarmOperation = nil
        }
        if config == nil || haCollectionSelectionChanged(stored.config, config) {
            let carCache = connectionChanged ? nil : stored.collectionCaches["car"]
            let carRead = connectionChanged ? nil : stored.collectionReads["car"]
            stored.collectionRevision = UUID().uuidString
            stored.collectionCaches = carCache.map { ["car": $0] } ?? [:]
            stored.collectionReads = carRead.map { ["car": $0] } ?? [:]
            if connectionChanged { clearCarRead(&stored) }
            stored.doorOperation = nil
            stored.doorActionRevision = UUID().uuidString
        }
        stored.config = config
    }

    /// Explicit sign-out/recovery discards an unreadable record and revokes every older request.
    /// Ordinary reads and merges never recover automatically or re-import legacy credentials.
    @discardableResult public func replaceConfig(_ config: HaConfig?) throws -> HaStoreSnapshot {
        try locked {
            let stored = Stored(config: config, scope: UUID().uuidString, readings: [:])
            try write(stored)
            return stored.snapshot
        }
    }

    /// nil explicitly means an obsolete request. It never activates the requesting generation.
    public func merge(_ readings: [String: HaStateReading], expectedScope: String,
                      expectedClimateRevision: String? = nil, expectedAlarmRevision: String? = nil,
                      expectedCollectionRevision: String? = nil,
                      failures: [String: String] = [:],
                      checkedAt: Date = .now) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope else { return nil }
            guard expectedCollectionRevision.map({ $0 == stored.collectionRevision }) ?? true else { return nil }
            let rejectClimate = stored.climateOperation?.pending == true
                || expectedClimateRevision.map({ $0 != stored.climateRevision }) == true
            let rejectAlarm = stored.alarmOperation?.pending == true
                || expectedAlarmRevision.map({ $0 != stored.alarmRevision }) == true
            let alarmEntities = Set([stored.config?.entityId, stored.config?.lockId].compactMap { $0 })
            for (id, value) in readings where value.entityID == id {
                if id == stored.config?.climateId && rejectClimate { continue }
                if alarmEntities.contains(id) && rejectAlarm { continue }
                if stored.readings[id].map({ $0.checkedAt <= value.checkedAt }) ?? true {
                    stored.readings[id] = value
                }
                if stored.failures[id].map({ $0.checkedAt <= value.checkedAt }) ?? false {
                    stored.failures.removeValue(forKey: id)
                }
            }
            for (id, message) in failures where !message.isEmpty {
                if id == stored.config?.climateId && rejectClimate { continue }
                if alarmEntities.contains(id) && rejectAlarm { continue }
                guard stored.readings[id].map({ $0.checkedAt <= checkedAt }) ?? true,
                      stored.failures[id].map({ $0.checkedAt <= checkedAt }) ?? true else { continue }
                stored.failures[id] = HaStateFailure(message: message, checkedAt: checkedAt)
            }
            try write(stored)
            return stored.snapshot
        }
    }

    public func beginCollectionRead(_ kind: String, expectedScope: String, expectedRevision: String,
                                    now: Date = .now) throws -> String? {
        if kind == "car" { try requireFiniteCarReadClock(now) }
        return try locked {
            var stored = try read()
            // Auto-discovered Car has no alarm/door selection; only its account generation owns it.
            let revision = kind == "car" ? stored.scope : stored.collectionRevision
            guard ["doors", "activity", "batteries", "car"].contains(kind),
                  stored.scope == expectedScope, revision == expectedRevision else { return nil }
            guard kind != "doors" || stored.doorOperation?.pending != true else { return nil }
            let readID = UUID().uuidString
            stored.collectionReads[kind] = readID
            if kind == "car" {
                stored.carRouteReadPrefix = nil
                stored.carReadLease = try newCarReadLease(readID: readID, now: now)
            }
            try write(stored)
            return readID
        }
    }

    /// One locked context check for route opening/reactivation. A newer same-car observation is
    /// compatible; account, missing/unidentified Car and different vehicle contexts are not.
    public func carRouteContext(expectedScope: String, expectedVehiclePrefix: String) throws -> HaStoreSnapshot? {
        try locked {
            let stored = try read()
            guard let prefix = normalizedCarVehiclePrefix(expectedVehiclePrefix),
                  carRouteMatches(stored, scope: expectedScope, prefix: prefix) else { return nil }
            return stored.snapshot
        }
    }

    /// Does not displace an active widget discovery or route lease; abandoned ownership is recovered
    /// under the lock. Ordinary discovery can supersede this owner without rebinding the route.
    public func beginCarRouteRead(expectedScope: String, expectedVehiclePrefix: String,
                                 now: Date = .now) throws -> HaCarRouteReadOwner? {
        try requireFiniteCarReadClock(now)
        return try locked {
            var stored = try read()
            guard let prefix = normalizedCarVehiclePrefix(expectedVehiclePrefix),
                  carRouteMatches(stored, scope: expectedScope, prefix: prefix) else { return nil }
            try recoverAbandonedCarRead(&stored, now: now)
            guard stored.collectionReads["car"] == nil else { return nil }
            let readID = UUID().uuidString
            stored.collectionReads["car"] = readID
            stored.carRouteReadPrefix = prefix
            stored.carReadLease = try newCarReadLease(readID: readID, now: now)
            try write(stored)
            return HaCarRouteReadOwner(scope: expectedScope, vehiclePrefix: prefix, readID: readID)
        }
    }

    /// Prefix validation, latest cache identity and request ownership are checked at the same commit
    /// point. An invalid target reply settles as a failure while keeping only same-target history.
    public func mergeCarRouteRead(_ owner: HaCarRouteReadOwner, reply: Result<String, HaError>,
                                 now: Date = .now) throws -> HaStoreSnapshot? {
        try requireFiniteCarReadClock(now)
        return try locked {
            var stored = try read()
            guard normalizedCarVehiclePrefix(owner.vehiclePrefix) == owner.vehiclePrefix,
                  carRouteMatches(stored, scope: owner.scope, prefix: owner.vehiclePrefix),
                  !owner.readID.isEmpty, stored.collectionReads["car"] == owner.readID,
                  stored.carRouteReadPrefix == owner.vehiclePrefix else { return nil }
            try recoverAbandonedCarRead(&stored, now: now)
            guard stored.collectionReads["car"] == owner.readID else { return nil }
            let checkedReply: Result<String, HaError>
            if case .success(let raw) = reply {
                if let identity = carReplyIdentity(raw) {
                    if !identity.found {
                        checkedReply = .failure(HaError("This car was not found · Refresh the widget to check"))
                    } else if identity.vehiclePrefix == owner.vehiclePrefix {
                        checkedReply = reply
                    } else {
                        checkedReply = .failure(HaError(identity.vehiclePrefix == nil
                            ? "Car could not be identified · Refresh the widget to check"
                            : "Car reply did not match this widget · Refresh the widget to check"))
                    }
                } else { checkedReply = .failure(HaError("Couldn't read car data")) }
            } else { checkedReply = reply }
            try settleCollection("car", reply: checkedReply, stored: &stored, now: now)
            return stored.snapshot
        }
    }

    public func failCarRouteRead(_ owner: HaCarRouteReadOwner, error: String, now: Date) throws -> HaStoreSnapshot? {
        try mergeCarRouteRead(owner, reply: .failure(HaError(error)), now: now)
    }

    private func carRouteMatches(_ stored: Stored, scope: String, prefix: String) -> Bool {
        guard stored.scope == scope, stored.config?.carReady == true,
              let cache = stored.collectionCaches["car"], let payload = cache.payload,
              let readings = try? JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8)),
              cache.observedAt == readings.checkedAt,
              let identity = carReplyIdentity(readings.current), identity.found,
              identity.vehiclePrefix == prefix else { return false }
        return true
    }

    private func requireFiniteCarReadClock(_ now: Date) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw HaError("Invalid Car refresh time") }
    }

    private func newCarReadLease(readID: String, now: Date) throws -> CarReadLease {
        let expiresAt = now.addingTimeInterval(Self.carReadLeaseDuration)
        guard expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSince(now) == Self.carReadLeaseDuration else {
            throw HaError("Invalid Car refresh time")
        }
        return CarReadLease(readID: readID, startedAt: now, expiresAt: expiresAt)
    }

    private func clearCarRead(_ stored: inout Stored) {
        stored.collectionReads.removeValue(forKey: "car")
        stored.carRouteReadPrefix = nil
        stored.carReadLease = nil
    }

    /// Recovery changes ownership only, leaving successful telemetry and all observation dates intact.
    private func recoverAbandonedCarRead(_ stored: inout Stored, now: Date) throws {
        if let readID = stored.collectionReads["car"],
           stored.carReadLease?.isActive(readID: readID, now: now) == true { return }
        guard stored.collectionReads["car"] != nil || stored.carRouteReadPrefix != nil
            || stored.carReadLease != nil else { return }
        clearCarRead(&stored)
        try write(stored)
    }

    public func adoptDoorDiscovery(_ ids: [String], expectedScope: String, expectedRevision: String,
                                   readID: String) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, stored.collectionRevision == expectedRevision,
                  !readID.isEmpty, stored.collectionReads["doors"] == readID,
                  var config = stored.config, config.carReady,
                  !config.doorsChosen, config.doorIds.isEmpty else { return nil }
            var seen = Set<String>()
            let selected = ids.filter { doorKindForID($0) != nil && seen.insert($0).inserted }
            guard !selected.isEmpty else { return stored.snapshot }
            config.doorIdsJson = String(data: try JSONEncoder().encode(selected), encoding: .utf8) ?? "[]"
            stored.config = config
            stored.collectionRevision = UUID().uuidString
            stored.doorActionRevision = UUID().uuidString
            let carCache = stored.collectionCaches["car"]
            let carRead = stored.collectionReads["car"]
            stored.collectionCaches = carCache.map { ["car": $0] } ?? [:]
            // Door discovery adopts its selection; account-owned Car is unrelated to that selection.
            stored.collectionReads = ["doors": readID]
            if let carRead { stored.collectionReads["car"] = carRead }
            try write(stored)
            return stored.snapshot
        }
    }

    public func mergeCollection(_ kind: String, reply: Result<String, HaError>, expectedScope: String,
                                expectedRevision: String, readID: String, now: Date = .now) throws -> HaStoreSnapshot? {
        if kind == "car" { try requireFiniteCarReadClock(now) }
        return try locked {
            var stored = try read()
            let revision = kind == "car" ? stored.scope : stored.collectionRevision
            guard stored.scope == expectedScope, revision == expectedRevision,
                  !readID.isEmpty, stored.collectionReads[kind] == readID,
                  kind != "car" || stored.carRouteReadPrefix == nil else { return nil }
            if kind == "car" {
                try recoverAbandonedCarRead(&stored, now: now)
                guard stored.collectionReads["car"] == readID else { return nil }
            }
            try settleCollection(kind, reply: reply, stored: &stored, now: now)
            return stored.snapshot
        }
    }

    /// The caller has already authorized scope, read owner and any route target under the sidecar lock.
    private func settleCollection(_ kind: String, reply: Result<String, HaError>, stored: inout Stored,
                                  now: Date) throws {
        let previous = stored.collectionCaches[kind]
        switch reply {
        case .success(let payload):
            if kind == "car" {
                do {
                    let previousReadings = previous?.payload.flatMap {
                        try? JSONDecoder().decode(CarReadingsCache.self, from: Data($0.utf8))
                    }
                    let readings = try carReadingsAfterReply(payload, previous: previousReadings, checkedAt: now)
                    let data = try JSONEncoder().encode(readings)
                    guard let encoded = String(data: data, encoding: .utf8) else { throw HaError("Couldn't save car data") }
                    stored.collectionCaches[kind] = HaCollectionCache(payload: encoded, observedAt: now, error: nil, attemptedAt: now)
                } catch {
                    stored.collectionCaches[kind] = HaCollectionCache(payload: previous?.payload, observedAt: previous?.observedAt,
                        error: friendlyError(error), attemptedAt: now)
                }
            } else {
                stored.collectionCaches[kind] = HaCollectionCache(payload: payload, observedAt: now, error: nil, attemptedAt: now)
            }
        case .failure(let failure):
            let message = failure.message.isEmpty ? "Couldn't read your home" : failure.message
            let recoveryMessage = kind == "car" && failure.code == 401 && !beaconNeedsSignIn(message)
                ? "Sign-in rejected: \(message)" : message
            stored.collectionCaches[kind] = HaCollectionCache(payload: previous?.payload, observedAt: previous?.observedAt,
                error: recoveryMessage, attemptedAt: now)
        }
        // A completion is single use; duplicate delivery cannot restamp the same observation.
        stored.collectionReads.removeValue(forKey: kind)
        if kind == "car" { clearCarRead(&stored) }
        try write(stored)
    }

    public func beginDoorOperation(expectedScope: String, expectedRevision: String, entityID: String,
                                   action: String, replacingID: String? = nil, now: Date = .now) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, stored.doorActionRevision == expectedRevision,
                  let config = stored.config, config.carReady, doorsSelectedIDs(config).contains(entityID),
                  let action = DoorAction(rawValue: action),
                  (action == .lock ? doorKindForID(entityID) == .lock : doorKindForID(entityID) == .garage)
            else { return nil }
            if let pending = stored.doorOperation, pending.pending {
                guard action == .stop, pending.entityID == entityID,
                      replacingID == pending.id,
                      ["open", "close"].contains(pending.action),
                      now.timeIntervalSince(pending.startedAt) >= 0,
                      now.timeIntervalSince(pending.startedAt) <= 90 else { return nil }
            } else if replacingID != nil { return nil }
            if var counterpart = stored.alarmOperation, counterpart.pending, counterpart.entityID == entityID {
                let age = now.timeIntervalSince(counterpart.startedAt)
                guard age > 90 || age < 0 else { return nil }
                counterpart.error = "Update interrupted · Refresh to check"
                stored.alarmOperation = counterpart
                stored.alarmRevision = UUID().uuidString
            }
            stored.doorActionRevision = UUID().uuidString
            stored.doorOperation = DoorOperation(entityID: entityID, action: action.rawValue, startedAt: now,
                actionRevision: stored.doorActionRevision)
            stored.collectionReads.removeValue(forKey: "doors")
            try write(stored)
            return stored.snapshot
        }
    }
    public func claimDoorDispatch(expectedScope: String, operationID: String) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, var operation = stored.doorOperation,
                  operation.id == operationID, operation.pending, !operation.delivered,
                  operation.actionRevision == stored.doorActionRevision else { return nil }
            operation.delivered = true
            stored.doorOperation = operation
            try write(stored)
            return stored.snapshot
        }
    }
    public func observeDoorOperation(expectedScope: String, operationID: String,
                                     reading: HaStateReading) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, let operation = stored.doorOperation, operation.pending,
                  operation.id == operationID, reading.entityID == operation.entityID,
                  reading.checkedAt >= operation.startedAt,
                  let parsed = doorFromState(reading.json), parsed.id == operation.entityID,
                  stored.config.map({ doorsSelectedIDs($0).contains(operation.entityID) }) == true else { return nil }
            if stored.readings[reading.entityID].map({ $0.checkedAt <= reading.checkedAt }) ?? true {
                stored.readings[reading.entityID] = reading
                if stored.failures[reading.entityID].map({ $0.checkedAt <= reading.checkedAt }) ?? false {
                    stored.failures.removeValue(forKey: reading.entityID)
                }
            }
            try write(stored)
            return stored.snapshot
        }
    }
    public func finishDoorOperation(expectedScope: String, operationID: String, error: String?,
                                    now: Date = .now) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, var operation = stored.doorOperation,
                  operation.id == operationID, operation.pending else { return nil }
            operation.endedAt = now
            operation.error = error.map { $0.isEmpty ? "Couldn't confirm · Refresh to check" : $0 }
            stored.doorOperation = operation
            try write(stored)
            return stored.snapshot
        }
    }
    public func expireDoorOperation(now: Date = .now) throws -> HaStoreSnapshot {
        try locked {
            var stored = try read()
            if var operation = stored.doorOperation, operation.pending,
               now.timeIntervalSince(operation.startedAt) > 90 || now < operation.startedAt {
                operation.endedAt = now
                operation.error = "Update interrupted · Refresh to check"
                stored.doorOperation = operation
                stored.collectionReads.removeValue(forKey: "doors")
                try write(stored)
            }
            return stored.snapshot
        }
    }

    /// A single transaction rejects duplicate taps and actions from a previously rendered card.
    public func beginClimateOperation(expectedScope: String, expectedRevision: String, entityID: String,
                                      action: String, resumeID: String? = nil, now: Date = .now) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, stored.climateRevision == expectedRevision,
                  let config = stored.config, config.hasClimate, config.climateId == entityID,
                  stored.climateOperation?.pending != true,
                  ["heatUp", "heatDown", "coolUp", "coolDown", "resume", "mode", "fan"].contains(action),
                  action != "resume" || (resumeID?.hasPrefix("button.") == true && config.resumeId == resumeID) else { return nil }
            stored.climateOperation = ClimateOperation(entityID: entityID, action: action, startedAt: now)
            stored.climateRevision = UUID().uuidString
            try write(stored)
            return stored.snapshot
        }
    }

    public func finishClimateOperation(expectedScope: String, operationID: String,
                                       error: String?) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, var operation = stored.climateOperation,
                  operation.id == operationID, operation.pending else { return nil }
            if let error {
                operation.error = error.isEmpty ? "Couldn't update thermostat" : error
                stored.climateOperation = operation
            } else { stored.climateOperation = nil }
            stored.climateRevision = UUID().uuidString
            try write(stored)
            return stored.snapshot
        }
    }

    /// An interrupted extension cannot leave every control disabled indefinitely. Never retries a command.
    public func expireClimateOperation(now: Date = .now) throws -> HaStoreSnapshot {
        try locked {
            var stored = try read()
            if var operation = stored.climateOperation, operation.pending,
               now.timeIntervalSince(operation.startedAt) > 90 {
                operation.error = "Update interrupted · Refresh to check"
                stored.climateOperation = operation
                stored.climateRevision = UUID().uuidString
                try write(stored)
            }
            return stored.snapshot
        }
    }

    /// Alarm and door share one operation: two conflicting security taps cannot execute together.
    public func beginAlarmOperation(expectedScope: String, expectedRevision: String, entityID: String,
                                    action: String, now: Date = .now) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, stored.alarmRevision == expectedRevision,
                  let config = stored.config, config.isComplete, stored.alarmOperation?.pending != true,
                  (AlarmAction(rawValue: action) != nil && config.entityId == entityID)
                    || (LockAction(rawValue: action) != nil && config.hasLock && config.lockId == entityID) else { return nil }
            if var counterpart = stored.doorOperation, counterpart.pending, counterpart.entityID == entityID {
                let age = now.timeIntervalSince(counterpart.startedAt)
                guard age > 90 || age < 0 else { return nil }
                counterpart.endedAt = now
                counterpart.error = "Update interrupted · Refresh to check"
                stored.doorOperation = counterpart
                stored.collectionReads.removeValue(forKey: "doors")
            }
            stored.alarmOperation = AlarmOperation(entityID: entityID, action: action, startedAt: now)
            stored.alarmRevision = UUID().uuidString
            try write(stored)
            return stored.snapshot
        }
    }

    /// Only the command's own validated live replies can update its telemetry while pending.
    public func observeAlarmOperation(expectedScope: String, operationID: String,
                                      reading: HaStateReading) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, let operation = stored.alarmOperation,
                  operation.id == operationID, operation.pending,
                  alarmObservation(reading, entityID: operation.entityID) != nil else { return nil }
            let id = operation.entityID
            if stored.readings[id].map({ $0.checkedAt <= reading.checkedAt }) ?? true {
                stored.readings[id] = reading
            }
            if stored.failures[id].map({ $0.checkedAt <= reading.checkedAt }) ?? false {
                stored.failures.removeValue(forKey: id)
            }
            try write(stored)
            return stored.snapshot
        }
    }

    public func failAlarmOperationRead(expectedScope: String, operationID: String,
                                       message: String, checkedAt: Date = .now) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, let operation = stored.alarmOperation,
                  operation.id == operationID, operation.pending else { return nil }
            let id = operation.entityID
            if (stored.readings[id].map({ $0.checkedAt <= checkedAt }) ?? true)
                && (stored.failures[id].map({ $0.checkedAt <= checkedAt }) ?? true) {
                stored.failures[id] = HaStateFailure(message: message, checkedAt: checkedAt)
            }
            try write(stored)
            return stored.snapshot
        }
    }

    public func finishAlarmOperation(expectedScope: String, operationID: String,
                                     error: String?) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope, var operation = stored.alarmOperation,
                  operation.id == operationID, operation.pending else { return nil }
            if let error {
                operation.error = error.isEmpty ? "Couldn't confirm · Refresh to check" : error
                stored.alarmOperation = operation
            } else { stored.alarmOperation = nil }
            stored.alarmRevision = UUID().uuidString
            try write(stored)
            return stored.snapshot
        }
    }

    /// Extension termination cannot leave the card pending forever; expiry never repeats a POST.
    public func expireAlarmOperation(now: Date = .now) throws -> HaStoreSnapshot {
        try locked {
            var stored = try read()
            if var operation = stored.alarmOperation, operation.pending,
               now.timeIntervalSince(operation.startedAt) > 90 {
                operation.error = "Update interrupted · Refresh to check"
                stored.alarmOperation = operation
                stored.alarmRevision = UUID().uuidString
                try write(stored)
            }
            return stored.snapshot
        }
    }

    private var file: URL { directory.appendingPathComponent("ha-state.json") }
    private func read() throws -> Stored {
        guard FileManager.default.fileExists(atPath: file.path) else {
            let initial = Stored(config: initialConfig, scope: initialScope, readings: [:])
            try write(initial)
            return initial
        }
        let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: file))
        guard stored.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return stored
    }
    private func write(_ stored: Stored) throws {
        let staged = directory.appendingPathComponent(".ha-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: staged) }
        try JSONEncoder().encode(stored).write(to: staged, options: .withoutOverwriting)
        try protect(staged, permissions: 0o600)
        // Protection is established before this single commit point. A failure leaves old data intact.
        guard rename(staged.path, file.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    private func protect(_ url: URL, permissions: Int) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protect(directory, permissions: 0o700)
        let lockURL = directory.appendingPathComponent("ha-state.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try protect(lockURL, permissions: 0o600)
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}
