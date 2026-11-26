import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ThermostatTicketLookup: Equatable, Sendable {
    case available(ThermostatTicket), expired, missing
}

/// The app and widget extension share immutable readings through exact, opaque ticket IDs.
/// Expiry never extends on access; oldest-first eviction of prior entries keeps the file bounded.
/// Every successful save retains its incoming ticket, including after a clock rollback.
public struct ThermostatTicketStore: Sendable {
    private let directory: URL
    private let maximumCount: Int
    private let maximumBytes: Int
    private let maximumTicketBytes: Int

    private struct Stored: Codable {
        var version = 1
        var tickets: [ThermostatTicket] = []
    }

    public init(directory: URL, maximumCount: Int = 32, maximumBytes: Int = 1024 * 1024,
                maximumTicketBytes: Int = 128 * 1024) {
        self.directory = directory
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
        self.maximumTicketBytes = maximumTicketBytes
    }

    /// Same-ID/same-payload retries are idempotent while the ticket remains live. A changed payload
    /// is never an update: it must be issued with a new UUID and its own fixed lifetime.
    public func save(_ ticket: ThermostatTicket, now: Date = .now) throws {
        try validateLimits(now: now)
        let encodedTicket = try encode(ticket)
        // Decoding checks the ticket's version, raw reading identity and timestamp coherence.
        _ = try JSONDecoder().decode(ThermostatTicket.self, from: encodedTicket)
        guard encodedTicket.count <= maximumTicketBytes else { throw ThermostatTicketError.oversized }
        guard now < ticket.expiresAt else { throw ThermostatTicketError.invalid }
        // If this ticket cannot fit alone, evicting other tickets would not make the save useful.
        guard try encode(Stored(tickets: [ticket])).count <= maximumBytes else {
            throw ThermostatTicketError.oversized
        }
        try locked {
            var stored = try read()
            if let existing = stored.tickets.first(where: { $0.id == ticket.id }) {
                guard existing == ticket else { throw ThermostatTicketError.duplicate }
                return
            }
            stored.tickets.removeAll { $0.expiresAt <= now }
            stored.tickets.sort {
                if $0.issuedAt != $1.issuedAt { return $0.issuedAt < $1.issuedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            if stored.tickets.count >= maximumCount {
                stored.tickets.removeFirst(stored.tickets.count - maximumCount + 1)
            }
            // Prior tickets remain in eviction order; the incoming ticket is last and cannot be
            // removed. The single-ticket budget check above guarantees it can fit on its own.
            stored.tickets.append(ticket)
            var data = try encode(stored)
            while data.count > maximumBytes {
                stored.tickets.removeFirst()
                data = try encode(stored)
            }
            try write(data)
        }
    }

    /// Missing, evicted and unknown IDs never fall back to today's account or newest Thermostat reading.
    /// Corrupt or unsupported storage throws so callers can present a nonoperating explanation.
    public func lookup(_ id: UUID, now: Date = .now) throws -> ThermostatTicketLookup {
        try validateLimits(now: now)
        return try locked {
            guard let ticket = try read().tickets.first(where: { $0.id == id }) else { return .missing }
            return now < ticket.expiresAt ? .available(ticket) : .expired
        }
    }

    private func validateLimits(now: Date) throws {
        guard maximumCount > 0, maximumBytes > 0, maximumTicketBytes > 0,
              now.timeIntervalSince1970.isFinite else { throw ThermostatTicketError.invalid }
    }

    private var file: URL { directory.appendingPathComponent("thermostat-readings-tickets.json") }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func read() throws -> Stored {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile
            || error.code == .fileNoSuchFile {
            return Stored()
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value <= Int64(maximumBytes) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try protect(file, permissions: 0o600)
        let data = try Data(contentsOf: file)
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.version == 1, stored.tickets.count <= maximumCount,
              Set(stored.tickets.map(\.id)).count == stored.tickets.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for ticket in stored.tickets {
            guard try encode(ticket).count <= maximumTicketBytes else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return stored
    }

    private func write(_ data: Data) throws {
        let staged = directory.appendingPathComponent(".thermostat-readings-tickets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .withoutOverwriting)
        try protect(staged, permissions: 0o600)
        // Establish protection before the single commit point; errors leave the old file intact.
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try protect(directory, permissions: 0o700)
        let lockURL = directory.appendingPathComponent("thermostat-readings-tickets.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
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
