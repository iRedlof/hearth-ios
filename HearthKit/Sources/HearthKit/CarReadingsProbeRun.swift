#if DEBUG
import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum CarRouteProbeSlot: String, Codable, Sendable, CaseIterable { case a = "A", b = "B" }
public enum CarRouteProbeScenario: String, Codable, Sendable, CaseIterable {
    case current, authentication, setup, persistenceFailure, expired
}

/// Compiled into both clients. A control file cannot choose the executable's identity.
public enum CarRouteProbeBuild {
    public static let marker = "car-route-probe-2026-10-31-v1"
}

public enum CarRouteProbeStorageError: Error, Sendable { case invalid, limitReached }

public struct CarRouteProbeRun: Codable, Equatable, Sendable {
    public let version: Int
    public let runID: UUID
    public let generation: UUID
    public let buildMarker: String
    public let scenario: CarRouteProbeScenario
    public let fixtureClock: Date
    public let slots: [CarRouteProbeSlot]

    public init(version: Int = 1, runID: UUID, generation: UUID,
                buildMarker: String = CarRouteProbeBuild.marker,
                scenario: CarRouteProbeScenario, fixtureClock: Date,
                slots: [CarRouteProbeSlot] = [.a, .b]) throws {
        let seconds = fixtureClock.timeIntervalSince1970
        guard version == 1, buildMarker.count <= 96, !buildMarker.isEmpty,
              buildMarker.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }),
              seconds.isFinite, seconds >= 946_684_800, seconds < 4_102_444_800,
              slots.count == 2, Set(slots) == Set([.a, .b]) else {
            throw CarRouteProbeStorageError.invalid
        }
        self.version = version; self.runID = runID; self.generation = generation
        self.buildMarker = buildMarker; self.scenario = scenario
        self.fixtureClock = fixtureClock; self.slots = slots
    }

    private enum CodingKeys: String, CodingKey {
        case version, runID, generation, buildMarker, scenario, fixtureClock, slots
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(version: values.decode(Int.self, forKey: .version),
            runID: values.decode(UUID.self, forKey: .runID),
            generation: values.decode(UUID.self, forKey: .generation),
            buildMarker: values.decode(String.self, forKey: .buildMarker),
            scenario: values.decode(CarRouteProbeScenario.self, forKey: .scenario),
            fixtureClock: values.decode(Date.self, forKey: .fixtureClock),
            slots: values.decode([CarRouteProbeSlot].self, forKey: .slots))
    }
}

public enum CarRouteProbeSelection: Equatable, Sendable {
    case inactive, armed(CarRouteProbeRun), blocked(String)
}
public enum CarRouteProbeControlRead: Equatable, Sendable {
    case absent, unavailable, invalid, disabled, active(CarRouteProbeRun)
}
public enum CarRouteProbeLaunchResolver {
    public static func scenario(arguments: [String]) -> CarRouteProbeScenario? {
        let indices = arguments.indices.filter { arguments[$0] == "-carWidgetProbe" }
        guard indices.count == 1, let index = indices.first, index + 1 < arguments.count else { return nil }
        return CarRouteProbeScenario(rawValue: arguments[index + 1])
    }

    /// Valid explicit arming is executed by the host; until activated it remains blocked here.
    public static func resolve(arguments: [String], isolationRequired: Bool,
                               control: CarRouteProbeControlRead) -> CarRouteProbeSelection {
        if arguments.contains("-carWidgetProbe"), scenario(arguments: arguments) == nil {
            return .blocked("The DEBUG Car probe scenario is missing or invalid.")
        }
        switch control {
        case .active(let run):
            guard run.buildMarker == CarRouteProbeBuild.marker else {
                return .blocked("The controlled run belongs to a different DEBUG build. Arm a new run.")
            }
            return .armed(run)
        case .disabled:
            return .blocked("The DEBUG Car probe is disabled. Isolation remains until an explicit reset.")
        case .invalid:
            return .blocked("The controlled run manifest or private folder is invalid. Arm a new run.")
        case .unavailable:
            return .blocked("The DEBUG Car probe shared storage cannot be opened.")
        case .absent:
            if isolationRequired || arguments.contains("-carWidgetProbe") {
                return .blocked("DEBUG Car probe isolation is required but no active controlled run is available.")
            }
            return .inactive
        }
    }
}

/// Only a private probe root is supplied. Run paths are derived solely from validated UUIDs.
public struct CarRouteProbeControlStore: Sendable {
    public let root: URL
    public static let maximumControlBytes = 64 * 1024
    public static let maximumRuns = 32
    public init(root: URL) { self.root = root }

    private struct Control: Codable {
        let version: Int
        let state: String
        let run: CarRouteProbeRun?
    }
    public func runDirectory(_ run: CarRouteProbeRun) -> URL {
        root.appendingPathComponent("Runs", isDirectory: true)
            .appendingPathComponent(run.runID.uuidString, isDirectory: true)
    }

    /// Preparation never activates, fetches, or creates a ticket. The caller seeds only private HA.
    public func prepare(_ run: CarRouteProbeRun) throws {
        try locked {
            guard run.buildMarker == CarRouteProbeBuild.marker else { throw CarRouteProbeStorageError.invalid }
            let runs = root.appendingPathComponent("Runs", isDirectory: true)
            try privateDirectory(runs)
            guard try FileManager.default.contentsOfDirectory(atPath: runs.path).count < Self.maximumRuns else {
                throw CarRouteProbeStorageError.limitReached
            }
            let folder = runDirectory(run)
            guard !FileManager.default.fileExists(atPath: folder.path) else { throw CarRouteProbeStorageError.invalid }
            try privateDirectory(folder)
            for child in ["HA", "Tickets", "Receipts", "Controls"] {
                try privateDirectory(folder.appendingPathComponent(child, isDirectory: true))
            }
            try write(encode(run), to: folder.appendingPathComponent("Controls/run.json"))
        }
    }

    /// The activation file is the final commit point after all required private preparation.
    public func activate(_ run: CarRouteProbeRun) throws {
        try locked {
            guard run.buildMarker == CarRouteProbeBuild.marker, try prepared(run) else {
                throw CarRouteProbeStorageError.invalid
            }
            try write(encode(Control(version: 1, state: "active", run: run)),
                to: root.appendingPathComponent("control.json"))
        }
    }
    public func setRefreshBarrier(run: CarRouteProbeRun, held: Bool) throws {
        try locked {
            guard isCurrent(run) else { throw CarRouteProbeStorageError.invalid }
            try write(encode(RefreshBarrier(version: 1, held: held)),
                to: runDirectory(run).appendingPathComponent("Controls/hold-refresh.json"))
        }
    }
    public func releaseRequest(run: CarRouteProbeRun, requestID: UUID) throws {
        try locked {
            guard isCurrent(run) else { throw CarRouteProbeStorageError.invalid }
            let controls = runDirectory(run).appendingPathComponent("Controls")
            guard try FileManager.default.contentsOfDirectory(atPath: controls.path).count < 128 else {
                throw CarRouteProbeStorageError.limitReached
            }
            try write(encode(RequestRelease(version: 1, requestID: requestID, released: true)),
                to: controls.appendingPathComponent("release-" + requestID.uuidString + ".json"))
        }
    }
    private struct RefreshBarrier: Codable { let version: Int; let held: Bool }
    private struct RequestRelease: Codable { let version: Int; let requestID: UUID; let released: Bool }
    fileprivate func refreshHeld(_ run: CarRouteProbeRun) throws -> Bool {
        guard let data = try boundedData(runDirectory(run).appendingPathComponent("Controls/hold-refresh.json")) else {
            return false
        }
        let barrier = try JSONDecoder().decode(RefreshBarrier.self, from: data)
        guard barrier.version == 1 else { throw CarRouteProbeStorageError.invalid }
        return barrier.held
    }
    fileprivate func requestReleased(_ run: CarRouteProbeRun, requestID: UUID) throws -> Bool {
        guard let data = try boundedData(runDirectory(run).appendingPathComponent(
            "Controls/release-" + requestID.uuidString + ".json")) else { return false }
        let release = try JSONDecoder().decode(RequestRelease.self, from: data)
        guard release.version == 1, release.requestID == requestID else { throw CarRouteProbeStorageError.invalid }
        return release.released
    }
    public func seedAndActivate(_ run: CarRouteProbeRun) throws {
        try prepare(run)
        let config = run.scenario == .setup ? nil
            : HaConfig(baseUrl: "https://fixture.example", token: "inert-fixture", entityId: "")
        let state = HaStateStore(directory: runDirectory(run).appendingPathComponent("HA"),
            initialConfig: config, initialScope: run.runID.uuidString)
        _ = try state.snapshot()
        try activate(run)
    }
    public func disable() throws {
        try locked {
            try write(encode(Control(version: 1, state: "disabled", run: nil)),
                to: root.appendingPathComponent("control.json"))
        }
    }
    public func read() -> CarRouteProbeControlRead {
        do {
            let file = root.appendingPathComponent("control.json")
            guard let data = try boundedData(file) else { return .absent }
            let control = try JSONDecoder().decode(Control.self, from: data)
            guard control.version == 1 else { return .invalid }
            if control.state == "disabled", control.run == nil { return .disabled }
            guard control.state == "active", let run = control.run, try prepared(run) else { return .invalid }
            return .active(run)
        } catch is DecodingError { return .invalid }
        catch is CarRouteProbeStorageError { return .invalid }
        catch { return .unavailable }
    }
    public func isCurrent(_ run: CarRouteProbeRun) -> Bool {
        run.buildMarker == CarRouteProbeBuild.marker && read() == .active(run)
    }

    private func prepared(_ run: CarRouteProbeRun) throws -> Bool {
        let folder = runDirectory(run)
        for directory in [root, root.appendingPathComponent("Runs"), folder]
            + ["HA", "Tickets", "Receipts", "Controls"].map({ folder.appendingPathComponent($0) }) {
            guard (try? FileManager.default.attributesOfItem(atPath: directory.path)[.type]
                as? FileAttributeType) == .typeDirectory else { return false }
        }
        guard let data = try boundedData(folder.appendingPathComponent("Controls/run.json")) else { return false }
        return try JSONDecoder().decode(CarRouteProbeRun.self, from: data) == run
    }
    private func boundedData(_ file: URL) throws -> Data? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file.path) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.int64Value <= Int64(Self.maximumControlBytes) else { throw CarRouteProbeStorageError.invalid }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumControlBytes + 1) ?? Data()
        guard data.count <= Self.maximumControlBytes else { throw CarRouteProbeStorageError.invalid }
        return data
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumControlBytes else { throw CarRouteProbeStorageError.invalid }
        return data
    }
    private func privateDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type]
                as? FileAttributeType == .typeDirectory else { throw CarRouteProbeStorageError.invalid }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try protect(directory, permissions: 0o700)
    }
    private func protect(_ url: URL, permissions: Int) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }
    private func write(_ data: Data, to file: URL) throws {
        let staged = file.deletingLastPathComponent().appendingPathComponent(".probe-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .withoutOverwriting)
        try protect(staged, permissions: 0o600)
        guard rename(staged.path, file.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try privateDirectory(root)
        let lock = root.appendingPathComponent("control.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try protect(lock, permissions: 0o600)
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}

/// One immutable identity per writer, one protected atomic file per receipt. No shared append.
public struct CarRouteProbeReceiptWriter: Sendable {
    public let run: CarRouteProbeRun
    public let slot: CarRouteProbeSlot?
    private let directory: URL
    private let maximumCount: Int
    private let maximumBytes: Int
    private static let processInstanceID = UUID()
    private static let phases: Set<String> = ["armed", "blocked", "providerCompleted", "widgetRendered",
        "sceneReceived", "screenLoaded", "refreshStarted", "requestEntered", "transportCompleted",
        "screenClosed", "sceneActive", "widgetRefreshRequested", "teslaDiscarded", "settingsStarted",
        "settingsReturned", "reconnectStarted", "reconnectReturned", "reconnectCancelled", "barrierReleased"]
    private static let fields: Set<String> = ["callbackKind", "entryID", "ticketID", "destination",
        "issuedAt", "expiresAt", "privateStoreID", "fetchCount", "saveCount", "transportCount", "ticketDigest",
        "snapshotName", "snapshotBattery", "observedAt", "displayedObservedAt", "attemptedAt",
        "requestEventID", "requestID", "lookupOutcome", "openingTicketID", "openingEntryID", "routeStatus",
        "scope", "prefix", "rawBattery", "rawName", "controlledResult", "transitionID", "routeEpoch",
        "accepted", "cancelled", "action", "reason", "lookupCount", "contextCount"]

    public init(run: CarRouteProbeRun, slot: CarRouteProbeSlot?, directory: URL,
                maximumCount: Int = 1024, maximumBytes: Int = 4 * 1024 * 1024) {
        self.run = run; self.slot = slot; self.directory = directory
        self.maximumCount = min(maximumCount, 1024); self.maximumBytes = min(maximumBytes, 4 * 1024 * 1024)
    }
    private struct Receipt: Encodable {
        let schemaVersion = 1
        let runID: UUID
        let generation: UUID
        let buildMarker: String
        let scenario: String
        let slot: String
        let eventID: UUID
        let phase: String
        let wallClock: Date
        let processInstanceID: UUID
        let processID: Int32
        let bundleID: String
        let fields: [String: String]
    }
    /// Event values have a closed schema, fixed bounds and no URL/token input channel.
    @discardableResult public func record(phase: String, fields: [String: String] = [:],
                                         eventID: UUID = UUID()) -> UUID? {
        guard Self.phases.contains(phase), maximumCount > 0, maximumBytes > 0 else { return nil }
        do {
            guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type]
                as? FileAttributeType == .typeDirectory else { return nil }
            let lock = directory.appendingPathComponent("receipts.lock")
            let descriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { return nil }
            defer { close(descriptor) }
            while flock(descriptor, LOCK_EX) != 0 {
                if errno == EINTR { continue }
                return nil
            }
            defer { _ = flock(descriptor, LOCK_UN) }
            let safe = fields.filter { key, value in
                Self.fields.contains(key) && value.utf8.count <= 1024
                    && !value.contains("://") && !value.contains("inert-fixture")
            }
            let receipt = Receipt(runID: run.runID, generation: run.generation, buildMarker: run.buildMarker,
                scenario: run.scenario.rawValue, slot: slot?.rawValue ?? "app", eventID: eventID, phase: phase,
                wallClock: .now, processInstanceID: Self.processInstanceID,
                processID: ProcessInfo.processInfo.processIdentifier,
                bundleID: Bundle.main.bundleIdentifier ?? "unknown", fields: safe)
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(receipt)
            guard data.count <= 16 * 1024 else { return nil }
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: nil).filter { $0.lastPathComponent != "receipts.lock" }
            var bytes = 0
            for file in files {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber,
                      size.int64Value >= 0, size.int64Value <= Int64(maximumBytes) else { return nil }
                bytes += size.intValue
                guard bytes <= maximumBytes else { return nil }
            }
            guard files.count < maximumCount, bytes + data.count <= maximumBytes else { return nil }
            let file = directory.appendingPathComponent(eventID.uuidString + ".json")
            guard !FileManager.default.fileExists(atPath: file.path) else { return nil }
            let staged = directory.appendingPathComponent(".receipt-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staged) }
            try data.write(to: staged, options: .withoutOverwriting)
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            try FileManager.default.setAttributes(attributes, ofItemAtPath: staged.path)
            guard rename(staged.path, file.path) == 0 else { return nil }
            return eventID
        } catch { return nil }
    }
    public static func ticketDigest(_ ticket: CarReadingsTicket) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(ticket)).map { String(format: "%02x", $0) }.joined()
    }
}

private final class CarRouteProbeCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var fetch = 0, save = 0, transport = 0
    var value: (fetch: Int, save: Int, transport: Int) {
        lock.lock(); defer { lock.unlock() }; return (fetch, save, transport)
    }
    func fetched() { lock.lock(); defer { lock.unlock() }; fetch += 1 }
    func saved() { lock.lock(); defer { lock.unlock() }; save += 1 }
    func requested() { lock.lock(); defer { lock.unlock() }; transport += 1 }
}

/// Captured private stores and nonoptional controlled transports for both the real loader and screen.
public struct CarRouteProbeDependencies: Sendable {
    public static let maximumHAStateBytes = 64 * 1024
    public let run: CarRouteProbeRun
    public let slot: CarRouteProbeSlot
    public let state: HaStateStore
    public let tickets: CarReadingsTicketStore
    public let issuanceClock: Date
    public let receipts: CarRouteProbeReceiptWriter
    public let request: @Sendable () async throws -> String
    public let fetchEnvelope: @Sendable () async -> CarLiveEnvelope
    public let persist: @Sendable (CarReadingsTicket, Date) throws -> Void
    public let allowsPublication: @Sendable () -> Bool
    private let counter: CarRouteProbeCounts
    public var counts: (fetch: Int, save: Int, transport: Int) { counter.value }

    public init(run: CarRouteProbeRun, slot: CarRouteProbeSlot, control: CarRouteProbeControlStore,
                barrierTimeout: TimeInterval = 30) throws {
        guard control.isCurrent(run), run.slots.contains(slot), barrierTimeout.isFinite,
              barrierTimeout > 0, barrierTimeout <= 30 else { throw CarRouteProbeStorageError.invalid }
        let folder = control.runDirectory(run)
        guard try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("HA/ha-state.json").path)[.type]
            as? FileAttributeType == .typeRegular else { throw CarRouteProbeStorageError.invalid }
        let state = HaStateStore(existingProbeDirectory: folder.appendingPathComponent("HA"),
            maximumProbeBytes: Self.maximumHAStateBytes)
        _ = try state.snapshot()
        let tickets = CarReadingsTicketStore(directory: folder.appendingPathComponent("Tickets"))
        let clock = run.scenario == .expired ? run.fixtureClock.addingTimeInterval(-172_860) : run.fixtureClock
        let receipts = CarRouteProbeReceiptWriter(run: run, slot: slot, directory: folder.appendingPathComponent("Receipts"))
        let transportReceipts = CarRouteProbeReceiptWriter(run: run, slot: nil,
            directory: folder.appendingPathComponent("Receipts"))
        let counter = CarRouteProbeCounts()
        let providerRequest: @Sendable () async throws -> String = {
            guard control.isCurrent(run) else { throw HaError("The controlled run is no longer active.") }
            counter.requested()
            if run.scenario == .authentication {
                throw HaError("Authentication failed. Sign in to Home Assistant again.", code: 401)
            }
            return try carRouteProbeReply(battery: slot == .a ? "79" : "44", clock: clock)
        }
        self.run = run; self.slot = slot; self.state = state; self.tickets = tickets
        self.issuanceClock = clock; self.receipts = receipts; self.counter = counter
        self.allowsPublication = { control.isCurrent(run) && (try? state.snapshot()) != nil }
        self.fetchEnvelope = {
            counter.fetched()
            guard control.isCurrent(run), let context = try? state.snapshot() else {
                return .storageUnavailable(now: clock)
            }
            return await fetchOwnedCarEnvelope(store: state, context: context, now: clock,
                request: providerRequest, observedNow: { clock })
        }
        self.persist = { ticket, date in
            counter.saved()
            guard control.isCurrent(run), date == clock else { throw CarRouteProbeStorageError.invalid }
            _ = try state.snapshot()
            if run.scenario == .persistenceFailure { throw CocoaError(.fileWriteNoPermission) }
            try tickets.save(ticket, now: date)
        }
        self.request = {
            try Task.checkCancellation()
            guard control.isCurrent(run) else { throw HaError("The controlled run is no longer active.") }
            _ = try state.snapshot()
            counter.requested()
            let requestID = UUID()
            transportReceipts.record(phase: "requestEntered", fields: ["requestID": requestID.uuidString, "action": "exactRefresh"],
                eventID: requestID)
            if try control.refreshHeld(run) {
                let deadline = Date().addingTimeInterval(barrierTimeout)
                while !(try control.requestReleased(run, requestID: requestID)) {
                    try Task.checkCancellation()
                    guard control.isCurrent(run) else { throw HaError("The controlled run is no longer active.") }
                    guard Date() < deadline else {
                        transportReceipts.record(phase: "transportCompleted", fields: ["requestID": requestID.uuidString,
                            "controlledResult": "barrierTimeout"])
                        throw HaError("The controlled Refresh barrier timed out.")
                    }
                    try await Task.sleep(for: .milliseconds(25))
                }
                transportReceipts.record(phase: "barrierReleased", fields: ["requestID": requestID.uuidString])
            }
            try Task.checkCancellation()
            guard control.isCurrent(run) else { throw HaError("The controlled run is no longer active.") }
            _ = try state.snapshot()
            if run.scenario == .authentication {
                transportReceipts.record(phase: "transportCompleted", fields: ["requestID": requestID.uuidString,
                    "controlledResult": "authenticationFailure"])
                throw HaError("Authentication failed. Sign in to Home Assistant again.", code: 401)
            }
            let raw = try carRouteProbeReply(battery: "80", clock: .now)
            transportReceipts.record(phase: "transportCompleted", fields: ["requestID": requestID.uuidString,
                "controlledResult": "controlledReply", "snapshotBattery": "80"])
            return raw
        }
    }
}

private func carRouteProbeReply(battery: String, clock: Date) throws -> String {
    var values = ["sensor.battery_level": battery, "sensor.battery_range": "242.3", "number.charge_limit": "80",
        "sensor.charging": "disconnected", "binary_sensor.charge_cable": "off", "sensor.charger_power": "0",
        "sensor.charge_energy_added": "7.4", "lock.lock": "locked", "switch.sentry_mode": "unknown",
        "device_tracker.location": "home", "binary_sensor.status": "off", "sensor.odometer": "12504.75",
        "sensor.inside_temperature": "69.5", "sensor.outside_temperature": "55.2", "climate.climate": "off"]
    for door in ["front_driver", "front_passenger", "rear_driver", "rear_passenger"] {
        values["binary_sensor.\(door)_door"] = "off"
    }
    for cover in ["frunk", "trunk", "windows", "charge_port_door"] { values["cover.\(cover)"] = "closed" }
    for wheel in ["front_left", "front_right", "rear_left", "rear_right"] {
        values["sensor.tire_pressure_\(wheel)"] = wheel == "rear_right" ? "unavailable" : "39.5"
        values["binary_sensor.tire_pressure_warning_\(wheel)"] = wheel == "rear_right" ? "unknown" : "off"
    }
    let object: [String: Any] = ["found": true, "prefix": "stargate",
        "name": "Stargate Premium — a long vehicle name for the full readings view", "s": values,
        "unit": "mi", "tempUnit": "°F", "pressureUnit": "psi",
        "statusSince": ISO8601DateFormatter().string(from: clock.addingTimeInterval(-3600))]
    return String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
}
#endif
