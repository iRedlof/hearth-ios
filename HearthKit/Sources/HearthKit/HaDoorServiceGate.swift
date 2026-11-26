import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Door transport uses a separate per-entity App Group sidecar, never the state-store lock.
public struct HaDoorServiceGate: Sendable {
    private let directory: URL
    private let entityID: String
    private let onContention: @Sendable () -> Void

    public init(directory: URL, entityID: String, onContention: @escaping @Sendable () -> Void = {}) {
        self.directory = directory; self.entityID = entityID; self.onContention = onContention
    }

    public func dispatch<T: Sendable>(isAuthorized: @Sendable () -> Bool,
        body: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data(entityID.utf8)).map { String(format: "%02x", $0) }.joined()
        let sidecar = directory.appendingPathComponent("ha-door-\(key).dispatch.lock")
        let descriptor = open(sidecar.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var acquired = false
        defer {
            if acquired { _ = flock(descriptor, LOCK_UN) }
            close(descriptor)
        }
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: sidecar.path)
        var notified = false
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno == EINTR { continue }
            guard errno == EWOULDBLOCK || errno == EAGAIN else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if !notified { notified = true; onContention() }
            try await Task.sleep(for: .milliseconds(20))
            try Task.checkCancellation()
        }
        acquired = true
        try Task.checkCancellation()
        guard isAuthorized() else { throw HaError("Configuration changed · Refresh to check") }
        // Hold only this separate entity gate across the request; the global store remains available
        // for exact Stop takeover. An older request finishes/cancels before Stop enters transport.
        return try await body()
    }
}
