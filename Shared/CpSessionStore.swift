import Foundation
import HearthKit

/// App-Group persistence for the ChargePoint session + auto-run record, shared app↔widget (mirrors
/// `HaConfigStore`). The `coulomb_sess` cookie rolls on every response, so `saveToken` updates just
/// the token in place.
enum CpSessionStore {
    private static var defaults: UserDefaults { UserDefaults(suiteName: "group.com.rohit.hearth") ?? .standard }
    private static let key = "cpSession"
    private static let runKey = "cpRun"
    private static let snapshotKey = "cpSnapshot"
    private static let operationKey = "cpOperation"
    private static let scopeKey = "cpRequestScope"
    private static let activityKey = "cpActivityRevision"

    /// Rolling cookies keep this identity; sign-in, sign-out and location changes replace it.
    static func requestScope() -> String { defaults.string(forKey: scopeKey) ?? "initial" }
    static func isCurrent(_ scope: String) -> Bool { requestScope() == scope }
    static func activityRevision() -> String { defaults.string(forKey: activityKey) ?? "initial" }
    private static func invalidateRequests() { defaults.set(UUID().uuidString, forKey: scopeKey) }
    private static func changedActivity() { defaults.set(UUID().uuidString, forKey: activityKey) }

    static func load() -> CpSession {
        guard let data = defaults.data(forKey: key),
              let session = try? JSONDecoder().decode(CpSession.self, from: data) else { return CpSession() }
        return session
    }

    static func save(_ session: CpSession) {
        invalidateRequests()
        defaults.removeObject(forKey: snapshotKey)
        if load().userId != session.userId {
            defaults.removeObject(forKey: runKey)
            defaults.removeObject(forKey: locKey)
            defaults.removeObject(forKey: operationKey)
            changedActivity()
        }
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: key) }
    }

    /// Persist just the rolled cookie (called from the client's `onToken`).
    static func saveToken(_ token: String) {
        var s = load(); s.token = token
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }
    static func saveToken(_ token: String, scope: String) {
        guard isCurrent(scope) else { return }
        saveToken(token)
    }
    static func markExpired(scope: String) {
        guard isCurrent(scope) else { return }
        var s = load(); s.expired = true; save(s)
    }

    static func clear() {
        invalidateRequests()
        changedActivity()
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: runKey)
        defaults.removeObject(forKey: locKey)
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: operationKey)
    }

    private static let locKey = "cpLocation"
    static func loadLocation() -> CpLocation? {
        guard let data = defaults.data(forKey: locKey) else { return nil }
        return try? JSONDecoder().decode(CpLocation.self, from: data)
    }
    static func saveLocation(_ loc: CpLocation?) {
        if loadLocation() != loc {
            invalidateRequests()
            defaults.removeObject(forKey: snapshotKey)
        }
        if let loc, let data = try? JSONEncoder().encode(loc) { defaults.set(data, forKey: locKey) }
        else { defaults.removeObject(forKey: locKey) }
    }

    static func loadRun() -> CpRun { cpRunFromWire(defaults.string(forKey: runKey) ?? "") }
    static func saveRun(_ run: CpRun) {
        changedActivity()
        defaults.set(cpRunToWire(run), forKey: runKey)
    }

    static func loadSnapshot() -> CpSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(CpSnapshot.self, from: data)
    }
    static func saveSnapshot(_ snapshot: CpSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: snapshotKey) }
    }
    static func loadOperation() -> CpOperation? {
        guard let data = defaults.data(forKey: operationKey) else { return nil }
        return try? JSONDecoder().decode(CpOperation.self, from: data)
    }
    static func saveOperation(_ operation: CpOperation?) {
        changedActivity()
        if let operation, let data = try? JSONEncoder().encode(operation) { defaults.set(data, forKey: operationKey) }
        else { defaults.removeObject(forKey: operationKey) }
    }

    /// Which auto-waitlist alerts to post (Android `note_*` prefs — each defaults ON when unset).
    private static func note(_ key: String) -> Bool { defaults.object(forKey: "note_" + key) as? Bool ?? true }
    static func loadAlertPrefs() -> CpAlertPrefs {
        CpAlertPrefs(offer: note("offer"), accepted: note("accepted"), snoozed: note("snoozed"), second: note("second"))
    }
    static func setAlert(_ key: String, _ on: Bool) { defaults.set(on, forKey: "note_" + key) }

    /// A stable device id for start/stop session calls (generated once, kept).
    static func udid() -> String {
        if let u = defaults.string(forKey: "cpUdid"), !u.isEmpty { return u }
        let u = UUID().uuidString
        defaults.set(u, forKey: "cpUdid")
        return u
    }
}
