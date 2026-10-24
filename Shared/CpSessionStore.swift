import Foundation
import HearthKit

/// App-Group persistence for the ChargePoint session + auto-run record, shared app↔widget (mirrors
/// `HaConfigStore`). The `coulomb_sess` cookie rolls on every response, so `saveToken` updates just
/// the token in place.
enum CpSessionStore {
    private static var defaults: UserDefaults { UserDefaults(suiteName: "group.com.rohit.hearth") ?? .standard }
    private static let key = "cpSession"
    private static let runKey = "cpRun"

    static func load() -> CpSession {
        guard let data = defaults.data(forKey: key),
              let session = try? JSONDecoder().decode(CpSession.self, from: data) else { return CpSession() }
        return session
    }

    static func save(_ session: CpSession) {
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: key) }
    }

    /// Persist just the rolled cookie (called from the client's `onToken`).
    static func saveToken(_ token: String) { var s = load(); s.token = token; save(s) }

    static func clear() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: runKey)
    }

    static func loadRun() -> CpRun { cpRunFromWire(defaults.string(forKey: runKey) ?? "") }
    static func saveRun(_ run: CpRun) { defaults.set(cpRunToWire(run), forKey: runKey) }

    /// A stable device id for start/stop session calls (generated once, kept).
    static func udid() -> String {
        if let u = defaults.string(forKey: "cpUdid"), !u.isEmpty { return u }
        let u = UUID().uuidString
        defaults.set(u, forKey: "cpUdid")
        return u
    }
}
