import XCTest
@testable import HearthKit

final class AlarmReadingsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func snapshot() -> AlarmSnapshot {
        var value = alarmSnapshot(alarm: AlarmState(state: "triggered", lastChanged: now.addingTimeInterval(-60)),
            lockState: "locked", lockChanged: now.addingTimeInterval(-90), name: "Family Home", error: nil,
            checkedAt: now.addingTimeInterval(-10), now: now, doorCheckedAt: now.addingTimeInterval(-20))
        value.entityID = "alarm_control_panel.home"; value.lockID = "lock.front"
        value.requestScope = "owner-a"; value.alarmRevision = "revision-a"
        return value
    }
    func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testTicketRetainsExactlyDisplayedReadingAndNeverFallsBackToNewest() throws {
        let store = AlarmReadingsTicketStore(directory: directory())
        let original = try AlarmReadingsTicket(snapshot: snapshot(), issuedAt: now)
        try store.save(original, now: now)
        var newer = snapshot(); newer.panelRawState = "disarmed"
        try store.save(AlarmReadingsTicket(snapshot: newer, issuedAt: now.addingTimeInterval(1)), now: now)
        XCTAssertEqual(try store.lookup(original.id, now: now), .available(original))
        XCTAssertEqual(try store.lookup(UUID(), now: now), .missing)
        XCTAssertEqual(try store.lookup(original.id, now: original.expiresAt), .expired)
    }
    func testOriginChangeOrUnavailableContextCannotOpenAsCurrent() throws {
        let ticket = try AlarmReadingsTicket(snapshot: snapshot(), issuedAt: now)
        let config = HaConfig(baseUrl: "https://example.invalid", token: "inert", entityId: "alarm_control_panel.home", lockId: "lock.front")
        let current = HaStoreSnapshot(config: config, scope: "owner-a", alarmRevision: "revision-a")
        XCTAssertEqual(alarmReadingsStatus(ticket, context: current, now: now), .current)
        XCTAssertEqual(alarmReadingsStatus(ticket, context: nil, now: now), .storageUnavailable)
        XCTAssertEqual(alarmReadingsStatus(ticket, context: HaStoreSnapshot(config: config, scope: "owner-b", alarmRevision: "revision-a"), now: now), .originChanged)
        XCTAssertEqual(alarmReadingsStatus(ticket, context: HaStoreSnapshot(config: config, scope: "owner-a", alarmRevision: "revision-b"), now: now), .originChanged)
    }
    func testUnboundInertExamplesNeverPersist() {
        var persisted = false
        let payload = bindAlarmReadingsEntry(AlarmSnapshot.sample, date: now) { _ in persisted = true }
        XCTAssertEqual(payload.destination, .inert); XCTAssertFalse(persisted)
    }
    func testSaveFailureRetainsWarningAndPublishesOnlyUnavailableExplanation() {
        let payload = bindAlarmReadingsEntry(snapshot(), date: now) { _ in throw HaError("Disk full") }
        XCTAssertEqual(payload.destination, .unavailable)
        XCTAssertEqual(alarmSmallContent(payload.snapshot, destination: payload.destination).criticalTexts, ["Alarm triggered", "Not saved"])
        XCTAssertEqual(payload.snapshot.panelRawState, "triggered")
    }
    func testOnlyOpaqueStrictDestinationsAreAccepted() throws {
        let id = UUID()
        let url = try XCTUnwrap(alarmReadingsURL(for: .ticket(id)))
        XCTAssertEqual(alarmReadingsDestination(from: url), .ticket(id))
        for suffix in ["?account=other", "#newest", "/next"] {
            XCTAssertNil(alarmReadingsDestination(from: URL(string: url.absoluteString + suffix)!))
        }
        XCTAssertNil(alarmReadingsURL(for: .inert))
        XCTAssertEqual(alarmReadingsDestination(from: URL(string: "hearth://alarm-readings/unavailable")!), .unavailable)
    }
    func testTicketRejectsFutureObservationAndInvalidOrigin() throws {
        var future = snapshot(); future.panelObservedAt = now.addingTimeInterval(1)
        XCTAssertThrowsError(try AlarmReadingsTicket(snapshot: future, issuedAt: now))
        var missing = snapshot(); missing.requestScope = ""
        XCTAssertThrowsError(try AlarmReadingsTicket(snapshot: missing, issuedAt: now))
    }
    func testRetainedTicketIsImmutableAndBounded() throws {
        let store = AlarmReadingsTicketStore(directory: directory(), maximumCount: 1)
        let first = try AlarmReadingsTicket(snapshot: snapshot(), issuedAt: now)
        try store.save(first, now: now)
        var changed = snapshot(); changed.name = "Different"
        XCTAssertThrowsError(try store.save(AlarmReadingsTicket(snapshot: changed, issuedAt: now, id: first.id), now: now))
        let next = try AlarmReadingsTicket(snapshot: snapshot(), issuedAt: now.addingTimeInterval(1))
        try store.save(next, now: now)
        XCTAssertEqual(try store.lookup(first.id, now: now), .missing)
        XCTAssertEqual(try store.lookup(next.id, now: now), .available(next))
    }
}
