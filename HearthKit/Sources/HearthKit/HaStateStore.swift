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

public struct HaStoreSnapshot: Sendable {
    public let config: HaConfig?
    public let scope: String
    public let readings: [String: HaStateReading]
    public let climateRevision: String
    public let climateOperation: ClimateOperation?
    public let failures: [String: HaStateFailure]
}

/// All readers and writers lock a permanent sidecar. The JSON file may then be replaced atomically
/// without changing the inode on which another process is waiting.
public struct HaStateStore: Sendable {
    private let directory: URL
    private let initialConfig: HaConfig?
    private let initialScope: String
    private struct Stored: Codable {
        var version = 1
        var config: HaConfig?
        var scope: String
        var readings: [String: HaStateReading]
        var climateRevision: String
        var climateOperation: ClimateOperation?
        var failures: [String: HaStateFailure]
        init(config: HaConfig?, scope: String, readings: [String: HaStateReading],
             climateRevision: String = UUID().uuidString, climateOperation: ClimateOperation? = nil,
             failures: [String: HaStateFailure] = [:]) {
            self.config = config; self.scope = scope; self.readings = readings
            self.climateRevision = climateRevision; self.climateOperation = climateOperation
            self.failures = failures
        }
        private enum CodingKeys: String, CodingKey { case version, config, scope, readings, climateRevision, climateOperation, failures }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            config = try values.decodeIfPresent(HaConfig.self, forKey: .config)
            scope = try values.decode(String.self, forKey: .scope)
            readings = try values.decode([String: HaStateReading].self, forKey: .readings)
            climateRevision = try values.decodeIfPresent(String.self, forKey: .climateRevision) ?? "legacy"
            climateOperation = try values.decodeIfPresent(ClimateOperation.self, forKey: .climateOperation)
            failures = try values.decodeIfPresent([String: HaStateFailure].self, forKey: .failures) ?? [:]
        }
        var snapshot: HaStoreSnapshot {
            HaStoreSnapshot(config: config, scope: scope, readings: readings,
                climateRevision: climateRevision, climateOperation: climateOperation, failures: failures)
        }
    }

    public init(directory: URL, initialConfig: HaConfig? = nil, initialScope: String = "initial") {
        self.directory = directory; self.initialConfig = initialConfig; self.initialScope = initialScope
    }

    public func snapshot() throws -> HaStoreSnapshot {
        try locked { try read().snapshot }
    }

    /// Account changes rotate the persisted generation even when signing back into the same account.
    /// Picker edits preserve the account scope and independently cached entity readings.
    @discardableResult public func saveConfig(_ config: HaConfig?) throws -> HaStoreSnapshot {
        try locked {
            var stored = try read()
            if config == nil || !haSameConnection(stored.config, config) {
                stored.scope = UUID().uuidString
                stored.readings = [:]
                stored.failures = [:]
            }
            if stored.config?.climateId != config?.climateId || stored.config?.resumeId != config?.resumeId
                || config == nil || !haSameConnection(stored.config, config) {
                stored.climateRevision = UUID().uuidString
                stored.climateOperation = nil
            }
            stored.config = config
            try write(stored)
            return stored.snapshot
        }
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
                      expectedClimateRevision: String? = nil, failures: [String: String] = [:],
                      checkedAt: Date = .now) throws -> HaStoreSnapshot? {
        try locked {
            var stored = try read()
            guard stored.scope == expectedScope else { return nil }
            let rejectClimate = stored.climateOperation?.pending == true
                || expectedClimateRevision.map({ $0 != stored.climateRevision }) == true
            for (id, value) in readings where value.entityID == id {
                if id == stored.config?.climateId && rejectClimate { continue }
                if stored.readings[id].map({ $0.checkedAt <= value.checkedAt }) ?? true {
                    stored.readings[id] = value
                }
                if stored.failures[id].map({ $0.checkedAt <= value.checkedAt }) ?? false {
                    stored.failures.removeValue(forKey: id)
                }
            }
            for (id, message) in failures where !message.isEmpty {
                if id == stored.config?.climateId && rejectClimate { continue }
                guard stored.readings[id].map({ $0.checkedAt <= checkedAt }) ?? true,
                      stored.failures[id].map({ $0.checkedAt <= checkedAt }) ?? true else { continue }
                stored.failures[id] = HaStateFailure(message: message, checkedAt: checkedAt)
            }
            try write(stored)
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
