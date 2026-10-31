import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// CP's record is independent of HA and shared by the app and extension through a permanent lock.
/// This foundation is not used by the legacy production CpSessionStore until its writers migrate.
public struct CpStateStore: Sendable {
    private let directory: URL
    private static let readLease: TimeInterval = 60
    private static let maximumStateBytes = 256 * 1024

    private struct StoredAlerts: Codable {
        var offer: Bool
        var accepted: Bool
        var snoozed: Bool
        var second: Bool
        init(_ value: CpAlertPrefs) {
            offer = value.offer; accepted = value.accepted; snoozed = value.snoozed; second = value.second
        }
        var value: CpAlertPrefs {
            CpAlertPrefs(offer: offer, accepted: accepted, snoozed: snoozed, second: second)
        }
    }

    private struct Stored: Codable {
        var version = 2
        var session: CpSession
        var location: CpLocation?
        var runWire: String
        var alerts: StoredAlerts
        var udid: String
        var context: CpContextStamp
        var reading: CpStoredReading?
        var failure: CpStateFailure?
        var activeRead: CpReadOwner?
        var signInOwner: CpSignInOwner?

        init(session: CpSession, location: CpLocation?, run: CpRun, alerts: CpAlertPrefs, udid: String) {
            self.session = session; self.location = location; runWire = cpRunToWire(run)
            self.alerts = StoredAlerts(alerts); self.udid = udid
            context = CpContextStamp(accountGeneration: UUID().uuidString, selectionRevision: UUID().uuidString,
                                     runID: UUID().uuidString, modeRevision: UUID().uuidString,
                                     settingsRevision: UUID().uuidString)
        }
        var snapshot: CpStoreSnapshot {
            CpStoreSnapshot(session: session, location: location, run: cpRunFromWire(runWire), alerts: alerts.value,
                udid: udid, context: context, reading: reading, failure: failure, activeRead: activeRead)
        }
        mutating func rotate(account: Bool = false, selection: Bool = false, run: Bool = false,
                             mode: Bool = false, settings: Bool = true) {
            context = CpContextStamp(
                accountGeneration: account ? UUID().uuidString : context.accountGeneration,
                selectionRevision: selection ? UUID().uuidString : context.selectionRevision,
                runID: run ? UUID().uuidString : context.runID,
                modeRevision: mode ? UUID().uuidString : context.modeRevision,
                settingsRevision: settings ? UUID().uuidString : context.settingsRevision)
        }
        mutating func retireReadings() {
            reading = nil; failure = nil; activeRead = nil
        }
    }

    public init(directory: URL) { self.directory = directory }

    public func snapshot(now: Date = .now) throws -> CpStoreSnapshot {
        try requireFinite(now)
        return try locked { try read().snapshot }
    }

    /// The marker is committed before importing. A crash in that gap requires signed-out recovery.
    public func bootstrap(legacy: CpLegacyState? = nil, now: Date = .now) throws -> CpStoreSnapshot {
        try requireFinite(now)
        return try locked {
            if try exists(file) { return try read().snapshot }
            guard try !exists(marker) else { throw CpStateStoreError.missingAuthoritativeState }
            try ensureMarker()
            let supplied = legacy?.session ?? CpSession()
            let hasCredential = supplied.userId > 0 && !supplied.token.isEmpty && supplied.renewedAt >= 0
            let session = hasCredential ? supplied : CpSession()
            let location = hasCredential && validLocation(legacy?.location) ? legacy?.location : nil
            var run = hasCredential ? validatedLegacyRun(legacy?.runWire ?? "") : CpRun()
            if session.expired || location == nil { run = cpPauseRun(run) }
            let stored = Stored(session: session, location: location, run: run,
                alerts: legacy?.alerts ?? CpAlertPrefs(),
                udid: legacy?.udid.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString)
            try write(stored)
            return stored.snapshot
        }
    }

    /// Only an explicit recovery surface should call this; it never reimports legacy credentials.
    public func recoverSignedOut(now: Date = .now) throws -> CpStoreSnapshot {
        try requireFinite(now)
        return try locked {
            let previous = try? read()
            try ensureMarker()
            let stored = Stored(session: CpSession(), location: nil, run: CpRun(),
                alerts: previous?.alerts.value ?? CpAlertPrefs(), udid: previous?.udid ?? UUID().uuidString)
            try write(stored)
            return stored.snapshot
        }
    }

    public func beginSignIn(expected: CpSettingsOrigin, now: Date = .now) throws -> CpSignInOwner? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.context == expected.context else { return nil }
            let owner = CpSignInOwner(accountGeneration: stored.context.accountGeneration, attemptID: UUID().uuidString)
            stored.signInOwner = owner
            try write(stored)
            return owner
        }
    }

    public func replaceSession(owner: CpSignInOwner, candidate: CpSession,
                               now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.signInOwner == owner, stored.context.accountGeneration == owner.accountGeneration,
                  candidate.isSignedIn, candidate.userId > 0, candidate.renewedAt >= 0 else { return nil }
            if stored.session.userId != candidate.userId {
                stored.location = nil
                stored.runWire = cpRunToWire(CpRun())
            }
            stored.session = candidate
            // Even same-user reauthentication cannot revive a request from the old cookie/account.
            stored.rotate(account: true, selection: true, run: true, mode: true)
            stored.retireReadings()
            stored.signInOwner = nil
            try write(stored)
            return stored.snapshot
        }
    }

    public func edit(expected: CpSettingsOrigin, edit: CpStoreEdit,
                     now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            switch edit {
            case .pause:
                // Read success and unrelated Settings changes do not authorize or prevent Pause.
                guard sameMode(stored.context, expected.context) else { return nil }
                var run = cpRunFromWire(stored.runWire)
                guard run.armed else { return stored.snapshot }
                run.armed = false
                stored.runWire = cpRunToWire(run)
                stored.rotate(mode: true)
            default:
                guard stored.context == expected.context else { return nil }
                switch edit {
                case .location(let location):
                    guard validLocation(location) else { return nil }
                    guard stored.location != location else { return stored.snapshot }
                    let changedTarget = !sameTarget(stored.location, location)
                    stored.location = location
                    if changedTarget {
                        stored.runWire = cpRunToWire(cpPauseRun(cpRunFromWire(stored.runWire)))
                        stored.rotate(selection: true, run: true, mode: true)
                        stored.retireReadings()
                        stored.signInOwner = nil
                    } else { stored.rotate() }
                case .locationName(let name):
                    guard let location = stored.location else { return nil }
                    guard location.label != name else { return stored.snapshot }
                    stored.location = CpLocation(name: location.name, address: location.address,
                        deviceIds: location.deviceIds, bounds: location.bounds,
                        city: location.city, state: location.state, label: name)
                    stored.rotate()
                case .signOut:
                    stored.session = CpSession(); stored.location = nil; stored.runWire = cpRunToWire(CpRun())
                    stored.rotate(account: true, selection: true, run: true, mode: true)
                    stored.retireReadings()
                    stored.signInOwner = nil
                case .alert(let key, let on):
                    switch key {
                    case .offer: stored.alerts.offer = on
                    case .accepted: stored.alerts.accepted = on
                    case .snoozed: stored.alerts.snoozed = on
                    case .second: stored.alerts.second = on
                    }
                    stored.rotate()
                case .pause: break
                }
            }
            try write(stored)
            return stored.snapshot
        }
    }

    public func beginRead(expected: CpContextStamp, now: Date = .now) throws -> CpReadOwner? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.context == expected, stored.session.isSignedIn else { return nil }
            let expiry = now.addingTimeInterval(Self.readLease)
            guard expiry.timeIntervalSinceReferenceDate.isFinite,
                  expiry.timeIntervalSince(now) == Self.readLease else { throw CpStateStoreError.invalidClock }
            let owner = CpReadOwner(accountGeneration: stored.context.accountGeneration,
                selectionRevision: stored.context.selectionRevision, readID: UUID().uuidString,
                startedAt: now, expiresAt: expiry)
            stored.activeRead = owner
            try write(stored)
            return owner
        }
    }

    public func commitRead(owner: CpReadOwner, provider: CpProviderReading, observedAt: Date,
                           now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        try requireFinite(observedAt)
        return try locked {
            var stored = try read()
            guard matches(stored, owner: owner, now: now),
                  observedAt >= owner.startedAt, observedAt <= now else { return nil }
            stored.reading = CpStoredReading(provider: provider, observedAt: observedAt)
            stored.failure = nil; stored.activeRead = nil
            try write(stored)
            return stored.snapshot
        }
    }

    public func failRead(owner: CpReadOwner, message: String, now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard matches(stored, owner: owner, now: now) else { return nil }
            stored.failure = CpStateFailure(message: message, attemptedAt: now)
            stored.activeRead = nil
            try write(stored)
            return stored.snapshot
        }
    }

    private func matches(_ stored: Stored, owner: CpReadOwner, now: Date) -> Bool {
        stored.activeRead == owner && stored.context.accountGeneration == owner.accountGeneration &&
            stored.context.selectionRevision == owner.selectionRevision &&
            owner.startedAt <= now && now < owner.expiresAt
    }

    private func sameMode(_ current: CpContextStamp, _ expected: CpContextStamp) -> Bool {
        current.accountGeneration == expected.accountGeneration && current.selectionRevision == expected.selectionRevision &&
            current.runID == expected.runID && current.modeRevision == expected.modeRevision
    }

    private func sameTarget(_ lhs: CpLocation?, _ rhs: CpLocation?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let a), .some(let b)): Set(a.deviceIds) == Set(b.deviceIds) && a.bounds == b.bounds
        default: false
        }
    }

    private func validLocation(_ location: CpLocation?) -> Bool {
        guard let location else { return true }
        let bounds = location.bounds
        return !location.deviceIds.isEmpty && location.deviceIds.allSatisfy { $0 > 0 } &&
            [bounds.swLat, bounds.swLon, bounds.neLat, bounds.neLon].allSatisfy(\.isFinite) &&
            bounds.swLat <= bounds.neLat && bounds.swLon <= bounds.neLon
    }

    private func validatedLegacyRun(_ wire: String) -> CpRun {
        guard validRunWire(wire) else { return CpRun() }
        return cpRunFromWire(wire)
    }

    private func validRunWire(_ wire: String) -> Bool {
        let parts = wire.split(separator: "|", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 8, [parts[0], parts[1], parts[2], parts[4]].allSatisfy({ $0 == "0" || $0 == "1" }),
              let startedAt = Int64(parts[3]), startedAt >= 0,
              parts[0] != "1" || startedAt > 0 else { return false }
        if !parts[6].isEmpty {
            guard let until = Int64(parts[6]), until >= 0 else { return false }
        }
        return true
    }

    private func requireFinite(_ now: Date) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw CpStateStoreError.invalidClock }
    }

    private var file: URL { directory.appendingPathComponent("cp-state.json") }
    private var marker: URL { directory.appendingPathComponent("cp-state.initialized") }

    private func read() throws -> Stored {
        guard try exists(file) else { throw CpStateStoreError.missingAuthoritativeState }
        let data = try readRegularFile(file)
        struct Header: Decodable { let version: Int }
        let version = try JSONDecoder().decode(Header.self, from: data).version
        guard version == 2 else { throw CpStateStoreError.unsupportedVersion }
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        let context = stored.context
        guard [context.accountGeneration, context.selectionRevision, context.runID, context.modeRevision,
               context.settingsRevision].allSatisfy({ UUID(uuidString: $0) != nil }),
              !stored.udid.isEmpty, validLocation(stored.location), validRunWire(stored.runWire),
              !cpRunFromWire(stored.runWire).armed || (stored.session.isSignedIn && stored.location != nil),
              stored.session.renewedAt >= 0,
              (stored.session.userId == 0 && stored.session.token.isEmpty) ||
                (stored.session.userId > 0 && !stored.session.token.isEmpty) else {
            throw CpStateStoreError.corrupt
        }
        if let reading = stored.reading { try requireFinite(reading.observedAt) }
        if let failure = stored.failure { try requireFinite(failure.attemptedAt) }
        if let owner = stored.activeRead {
            try requireFinite(owner.startedAt); try requireFinite(owner.expiresAt)
            guard UUID(uuidString: owner.readID) != nil,
                  owner.accountGeneration == context.accountGeneration,
                  owner.selectionRevision == context.selectionRevision,
                  owner.expiresAt.timeIntervalSince(owner.startedAt) == Self.readLease else {
                throw CpStateStoreError.corrupt
            }
        }
        if let owner = stored.signInOwner {
            guard owner.accountGeneration == context.accountGeneration, UUID(uuidString: owner.attemptID) != nil else {
                throw CpStateStoreError.corrupt
            }
        }
        try ensureMarker()
        return stored
    }

    private func ensureMarker() throws {
        if try exists(marker) {
            _ = try readRegularFile(marker)
            try protect(marker, permissions: 0o600)
        } else {
            try replace(Data("initialized\n".utf8), at: marker)
        }
    }

    private func write(_ stored: Stored) throws {
        let data = try JSONEncoder().encode(stored)
        guard data.count <= Self.maximumStateBytes else { throw CpStateStoreError.corrupt }
        try replace(data, at: file)
    }

    /// Establish protection before the single rename commit point. Never replace the lock inode.
    private func replace(_ data: Data, at target: URL) throws {
        let staged = directory.appendingPathComponent(".cp-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .withoutOverwriting)
        try protect(staged, permissions: 0o600)
        guard rename(staged.path, target.path) == 0 else { throw posixError() }
    }

    private func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw posixError()
    }

    /// Bounded regular-file reads cannot hang on a FIFO or follow a replaced credential symlink.
    private func readRegularFile(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_size >= 0,
              info.st_size <= off_t(Self.maximumStateBytes) else { throw CpStateStoreError.corrupt }
        let expectedSize = Int(info.st_size)
        var data = Data(count: expectedSize + 1)
        var received = 0
        while received < data.count {
            let remaining = data.count - received
            let amount = data.withUnsafeMutableBytes { bytes in
                #if canImport(Darwin)
                Darwin.read(descriptor, bytes.baseAddress!.advanced(by: received), remaining)
                #else
                Glibc.read(descriptor, bytes.baseAddress!.advanced(by: received), remaining)
                #endif
            }
            if amount < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if amount == 0 { break }
            received += amount
        }
        guard received == expectedSize else { throw CpStateStoreError.corrupt }
        data.count = received
        return data
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
        let sidecar = directory.appendingPathComponent("cp-state.lock")
        let descriptor = open(sidecar.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw CpStateStoreError.corrupt }
        try protect(sidecar, permissions: 0o600)
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw posixError()
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
