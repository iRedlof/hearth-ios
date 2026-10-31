import Foundation
import HearthKit

#if DEBUG
/// Installed only by the native ownership harness before it constructs an actual CP intent/view.
struct CpOwnedFixtureDependencies: Sendable {
    let directory: URL
    let suiteName: String
    let transport: any CpOwnedTransport
    let now: @Sendable () -> Date
    let onAlert: @Sendable (CpAlert, CpStoreSnapshot) -> Void
    let onReload: @Sendable () -> Void
    let onPermission: @Sendable () -> Void
}

private final class CpOwnedFixtureRegistry: @unchecked Sendable {
    static let shared = CpOwnedFixtureRegistry()
    private let lock = NSLock()
    private var value: CpOwnedFixtureDependencies?
    func load() -> CpOwnedFixtureDependencies? { lock.withLock { value } }
    func install(_ dependencies: CpOwnedFixtureDependencies) { lock.withLock { value = dependencies } }
    func discard() { lock.withLock { value = nil } }
}
#endif

/// Production App Group boundary. Every CP reader/writer resolves one coherent owned record.
enum CpSessionStore {
    #if DEBUG
    static var fixtureActive: Bool { ProcessInfo.processInfo.arguments.contains("--cp-owned-native-fixture") }

    static func installFixture(_ dependencies: CpOwnedFixtureDependencies) throws {
        let prefix = "cp-owned-native-"
        let resolved = dependencies.directory.resolvingSymlinksInPath().standardizedFileURL
        let parent = resolved.deletingLastPathComponent()
        let name = dependencies.directory.lastPathComponent
        guard fixtureActive,
              parent == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              resolved.lastPathComponent == name,
              name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil,
              dependencies.suiteName == name else { throw CpStateStoreError.ownershipUnavailable }
        CpOwnedFixtureRegistry.shared.install(dependencies)
    }

    static func discardFixtureDependencies() { CpOwnedFixtureRegistry.shared.discard() }

    private static func fixtureDependencies() throws -> CpOwnedFixtureDependencies? {
        guard fixtureActive else { return nil }
        guard let dependencies = CpOwnedFixtureRegistry.shared.load() else { throw CpStateStoreError.ownershipUnavailable }
        return dependencies
    }
    #endif

    static func encodedActionOrigin(_ origin: CpRenderedOrigin?) -> String {
        guard let origin else { return "" }
        #if DEBUG
        guard (try? fixtureDependencies()) != nil || !fixtureActive else { return "" }
        return CpActionOriginEnvelope.encode(origin, inFixture: fixtureActive) ?? ""
        #else
        return CpActionOriginEnvelope.encode(origin, inFixture: false) ?? ""
        #endif
    }

    static func actionOrigin(_ encoded: String) -> CpRenderedOrigin? {
        #if DEBUG
        guard (try? fixtureDependencies()) != nil || !fixtureActive else { return nil }
        return CpActionOriginEnvelope.decode(encoded, inFixture: fixtureActive)
        #else
        return CpActionOriginEnvelope.decode(encoded, inFixture: false)
        #endif
    }

    /// Even a lost fixture dependency cannot fall through into real timeline/defaults effects.
    static func fixtureReloadHandled() -> Bool {
        #if DEBUG
        if fixtureActive {
            CpOwnedFixtureRegistry.shared.load()?.onReload()
            return true
        }
        #endif
        return false
    }

    static func requestOwnedNotificationPermission() {
        #if DEBUG
        if fixtureActive {
            CpOwnedFixtureRegistry.shared.load()?.onPermission()
            return
        }
        #endif
        CpNotify.requestPermission()
    }

    static func directory() throws -> URL {
        #if DEBUG
        if let fixture = try fixtureDependencies() { return fixture.directory }
        #endif
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.rohit.hearth") else {
            throw HaError("ChargePoint shared storage is unavailable")
        }
        return container.appendingPathComponent("ChargePoint", isDirectory: true)
    }

    static func repository() throws -> CpAppGroupRepository {
        #if DEBUG
        if let fixture = try fixtureDependencies() {
            guard let defaults = UserDefaults(suiteName: fixture.suiteName) else { throw CpStateStoreError.ownershipUnavailable }
            return try CpAppGroupRepository(directory: fixture.directory, legacyDefaults: defaults, now: fixture.now())
        }
        #endif
        guard let defaults = UserDefaults(suiteName: "group.com.rohit.hearth") else {
            throw HaError("ChargePoint shared storage is unavailable")
        }
        return try CpAppGroupRepository(directory: directory(), legacyDefaults: defaults)
    }

    static func context() throws -> CpStoreSnapshot { try repository().store.snapshot() }

    static func runtime(now: @escaping @Sendable () -> Date = { .now }) throws -> CpOwnedRuntime {
        #if DEBUG
        if let fixture = try fixtureDependencies() {
            guard let defaults = UserDefaults(suiteName: fixture.suiteName) else { throw CpStateStoreError.ownershipUnavailable }
            let repository = try CpAppGroupRepository(directory: fixture.directory, legacyDefaults: defaults, now: fixture.now())
            return CpOwnedRuntime(store: repository.store, directory: repository.directory,
                transport: fixture.transport, now: fixture.now, onAlert: fixture.onAlert)
        }
        #endif
        let repository = try repository()
        return CpOwnedRuntime(store: repository.store, directory: repository.directory, now: now) { alert, snapshot in
            guard cpAlertAllowed(alert, prefs: snapshot.alerts) else { return }
            let display = try? snapshot.displaySnapshot(now: now())
            let who = display?.goTo ?? "your charger"
            let by = display?.deadline.map { date in
                let formatter = DateFormatter(); formatter.dateFormat = "h:mm a"; return formatter.string(from: date)
            } ?? "the deadline"
            let content = cpAlertContent(alert, who: who, by: by)
            CpNotify.post(title: content.title, body: content.body, id: content.id)
        }
    }

    /// Explicit recovery never imports old credential keys.
    static func recoverSignedOut() throws {
        _ = try CpStateStore(directory: directory()).recoverSignedOut()
        _ = try repository()
    }

    static var unavailableSnapshot: CpSnapshot {
        CpSnapshot(site: "ChargePoint", account: "Unavailable", bigAnswer: "Unavailable", unit: "",
            sub: "Shared storage unavailable · Open Hearth to recover", plugsFree: nil, autoOn: false,
            actionLabel: "Open", stale: true)
    }
}
