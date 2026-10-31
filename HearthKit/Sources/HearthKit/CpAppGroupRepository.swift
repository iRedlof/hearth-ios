import Foundation

/// One-time split-key import; an authoritative marker prevents credential resurrection thereafter.
/// The caller must provide the real App Group directory and suite. There is no standard-defaults fallback.
public struct CpAppGroupRepository: Sendable {
    public let store: CpStateStore
    public let directory: URL

    public init(directory: URL, legacyDefaults: UserDefaults, now: Date = .now) throws {
        self.directory = directory
        store = CpStateStore(directory: directory)
        func decoded<T: Decodable>(_ key: String, _: T.Type) -> T? {
            legacyDefaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        }
        func note(_ key: String) -> Bool { legacyDefaults.object(forKey: "note_" + key) as? Bool ?? true }
        let legacy = CpLegacyState(session: decoded("cpSession", CpSession.self),
            location: decoded("cpLocation", CpLocation.self), runWire: legacyDefaults.string(forKey: "cpRun") ?? "",
            alerts: CpAlertPrefs(offer: note("offer"), accepted: note("accepted"), snoozed: note("snoozed"), second: note("second")),
            udid: legacyDefaults.string(forKey: "cpUdid"),
            pendingOperation: decoded("cpOperation", CpOperation.self) ??
                (legacyDefaults.object(forKey: "cpOperation") == nil ? nil : CpOperation(command: "legacy", startedAt: now)))
        _ = try store.bootstrap(legacy: legacy, now: now)
        for key in ["cpSession", "cpLocation", "cpRun", "cpSnapshot", "cpOperation", "cpRequestScope",
                    "cpActivityRevision", "cpUdid", "note_offer", "note_accepted", "note_snoozed", "note_second"] {
            if legacyDefaults.object(forKey: key) != nil { legacyDefaults.removeObject(forKey: key) }
        }
    }
}
