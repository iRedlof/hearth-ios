import Foundation

public enum AlarmReadingsDestination: Sendable, Equatable { case ticket(UUID), unavailable, inert }
public enum AlarmReadingsTicketError: Error { case invalid, oversized, duplicate }
public struct AlarmReadingsTicket: Codable, Sendable, Equatable, Identifiable {
    public let version: Int
    public let id: UUID
    public let issuedAt, expiresAt: Date
    public let snapshot: AlarmSnapshot
    public init(snapshot: AlarmSnapshot, issuedAt: Date = .now, id: UUID = UUID()) throws {
        version = 1; self.id = id; self.issuedAt = issuedAt
        expiresAt = issuedAt.addingTimeInterval(48 * 3600); self.snapshot = snapshot
        try validate()
    }
    private enum CodingKeys: String, CodingKey { case version, id, issuedAt, expiresAt, snapshot }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version); id = try values.decode(UUID.self, forKey: .id)
        issuedAt = try values.decode(Date.self, forKey: .issuedAt); expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        snapshot = try values.decode(AlarmSnapshot.self, forKey: .snapshot)
        try validate()
    }
    private func validate() throws {
        guard version == 1, issuedAt.timeIntervalSince1970.isFinite,
              expiresAt.timeIntervalSince(issuedAt) == 48 * 3600,
              !snapshot.requestScope.isEmpty, !snapshot.alarmRevision.isEmpty,
              snapshot.entityID.isEmpty && snapshot.setup || snapshot.entityID.hasPrefix("alarm_control_panel."),
              snapshot.lockID.isEmpty || snapshot.lockID.hasPrefix("lock.") else { throw AlarmReadingsTicketError.invalid }
        for date in [snapshot.panelObservedAt, snapshot.doorObservedAt, snapshot.operation?.startedAt].compactMap({ $0 }) {
            guard date.timeIntervalSince1970.isFinite, date <= issuedAt else { throw AlarmReadingsTicketError.invalid }
        }
        if let operation = snapshot.operation {
            guard !operation.id.isEmpty, operation.entityID == snapshot.entityID || operation.entityID == snapshot.lockID else {
                throw AlarmReadingsTicketError.invalid
            }
        }
    }
}
public struct AlarmReadingsEntryPayload: Sendable {
    public let date: Date
    public let snapshot: AlarmSnapshot
    public let destination: AlarmReadingsDestination
    public init(date: Date, snapshot: AlarmSnapshot, destination: AlarmReadingsDestination) {
        self.date = date; self.snapshot = snapshot; self.destination = destination
    }
}
public func bindAlarmReadingsEntry(_ snapshot: AlarmSnapshot, date: Date = .now,
                                  persist: (AlarmReadingsTicket) throws -> Void) -> AlarmReadingsEntryPayload {
    guard !snapshot.requestScope.isEmpty, !snapshot.alarmRevision.isEmpty else {
        return AlarmReadingsEntryPayload(date: date, snapshot: snapshot, destination: .inert)
    }
    let destination: AlarmReadingsDestination
    do {
        let ticket = try AlarmReadingsTicket(snapshot: snapshot, issuedAt: date)
        try persist(ticket); destination = .ticket(ticket.id)
    } catch { destination = .unavailable }
    return AlarmReadingsEntryPayload(date: date, snapshot: snapshot, destination: destination)
}
public func alarmReadingsURL(for destination: AlarmReadingsDestination) -> URL? {
    switch destination {
    case .ticket(let id): URL(string: "hearth://alarm-readings/\(id.uuidString)")
    case .unavailable: URL(string: "hearth://alarm-readings/unavailable")
    case .inert: nil
    }
}
public func alarmReadingsDestination(from url: URL) -> AlarmReadingsDestination? {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          parts.scheme == "hearth", parts.host == "alarm-readings", parts.user == nil,
          parts.password == nil, parts.port == nil, parts.query == nil, parts.fragment == nil,
          url.absoluteString == "hearth://alarm-readings\(parts.percentEncodedPath)",
          !parts.percentEncodedPath.contains("%") else { return nil }
    if parts.path == "/unavailable" { return .unavailable }
    guard parts.path.first == "/", let id = UUID(uuidString: String(parts.path.dropFirst())) else { return nil }
    return .ticket(id)
}
public enum AlarmReadingsStatus: Sendable, Equatable { case current, originChanged, expired, storageUnavailable }
/// Read-only navigation never reconciles a saved entry to newer telemetry.
public func alarmReadingsStatus(_ ticket: AlarmReadingsTicket, context: HaStoreSnapshot?, now: Date = .now) -> AlarmReadingsStatus {
    guard now.timeIntervalSince1970.isFinite, now < ticket.expiresAt else { return .expired }
    guard let context else { return .storageUnavailable }
    let shown = ticket.snapshot
    guard shown.requestScope == context.scope, shown.alarmRevision == context.alarmRevision,
          shown.entityID == (context.config?.entityId ?? ""),
          shown.lockID == (context.config?.hasLock == true ? context.config?.lockId ?? "" : "") else { return .originChanged }
    return .current
}
