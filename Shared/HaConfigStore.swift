import Foundation
import HearthKit

/// The app and extension capture configuration and account scope from one locked App Group record.
public enum HaConfigStore {
    public static let appGroup = "group.com.rohit.hearth"
    private static let key = "haConfig"
    private static let scopeKey = "haRequestScope"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var store: HaStateStore? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let legacy = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HaConfig.self, from: $0) }
        return HaStateStore(directory: container.appendingPathComponent("Library/Application Support/HAState"),
            initialConfig: legacy, initialScope: defaults.string(forKey: scopeKey) ?? "initial")
    }
    static func context() -> HaStoreSnapshot? { try? store?.snapshot() }
    static func climateContext(now: Date = .now) throws -> HaStoreSnapshot {
        guard let store else { throw HaError("Shared storage is unavailable") }
        return try store.expireClimateOperation(now: now)
    }
    static func alarmContext(now: Date = .now) throws -> HaStoreSnapshot {
        guard let store else { throw HaError("Shared storage is unavailable") }
        return try store.expireAlarmOperation(now: now)
    }

    public static func load() -> HaConfig? {
        context()?.config
    }

    public static func save(_ config: HaConfig) throws {
        let data = try JSONEncoder().encode(config)
        guard let store else { throw HaError("Shared storage is unavailable. Please reopen Hearth.") }
        let before = context()
        let saved: HaStoreSnapshot
        do { saved = try store.saveConfig(config) }
        catch is DecodingError { saved = try store.replaceConfig(config) }
        catch let error as CocoaError where error.code == .fileReadCorruptFile {
            saved = try store.replaceConfig(config)
        }
        if saved.scope != before?.scope { CarLiveSnapshot.clear() }
        // Kept as a one-time migration source for older installations. Reads use the file context.
        defaults.set(data, forKey: key)
        defaults.set(saved.scope, forKey: scopeKey)
    }

    /// Stable across entity-picker edits, replaced when signing out or changing server/account.
    public static func requestScope() -> String { context()?.scope ?? "unavailable" }
    public static func isCurrent(_ scope: String, config: HaConfig?) -> Bool {
        guard let current = context() else { return false }
        return current.scope == scope && haSameConnection(current.config, config)
    }
    public static func clear() throws {
        guard let store else { throw HaError("Shared storage is unavailable. Please reopen Hearth.") }
        let saved = try store.replaceConfig(nil)
        CarLiveSnapshot.clear()
        defaults.removeObject(forKey: key)
        defaults.set(saved.scope, forKey: scopeKey)
    }
}
