import Foundation
import Testing
@testable import HearthKit

/// The Alarm card's Garage row: what it says and which button it offers for every cover state.
@Suite("Alarm garage row")
struct AlarmGarageRowTests {
    private static let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private static let locale = Locale(identifier: "en_US")
    /// 2026-10-21 09:46 in Los Angeles.
    private static let now = Date(timeIntervalSince1970: 1_792_601_160)
    private static let checked = now.addingTimeInterval(-300)
    private static let garageID = "cover.garage"
    private static let panelID = "alarm_control_panel.home"
    private static let lockID = "lock.front"

    private static func garageJSON(_ state: String, features: String? = "11", id: String = garageID,
                                   deviceClass: String = "garage") -> String {
        let mask = features.map { #","supported_features":\#($0)"# } ?? ""
        return #"{"entity_id":"\#(id)","state":"\#(state)","last_changed":"2026-10-21T16:20:00Z","#
            + #""attributes":{"friendly_name":"Garage","device_class":"\#(deviceClass)"\#(mask)}}"#
    }
    private static func reading(_ state: String, features: String? = "11", at: Date = checked) -> HaStateReading {
        HaStateReading(entityID: garageID, json: garageJSON(state, features: features), checkedAt: at)
    }
    private static func row(_ reading: HaStateReading?, error: String? = nil) -> AlarmGarageRow {
        alarmGarageRow(entityID: garageID, reading: reading, error: error, now: now, zone: zone, locale: locale)
    }

    @Test("A closed garage offers Open and says since when")
    func closed() {
        let row = Self.row(Self.reading("closed"))
        #expect(row.name == "Garage")
        #expect(row.state == "Closed")
        #expect(row.since == "since 9:20 AM")
        #expect(row.open == false)
        #expect(!row.moving)
        #expect(row.action == .open)
        #expect(!row.stale)
        #expect(alarmDoorStatusLines(state: row.state, since: row.since, stale: row.stale)
            == ["Closed · since 9:20 AM", "Closed · 9:20 AM", "Closed"])
    }

    @Test("An open garage offers Close")
    func open() {
        let row = Self.row(Self.reading("open"))
        #expect(row.state == "Open")
        #expect(row.since == "since 9:20 AM")
        #expect(row.open == true)
        #expect(row.action == .close)
    }

    @Test("A moving garage offers Stop and has no since", arguments: [("opening", "Opening…"), ("closing", "Closing…")])
    func moving(state: String, word: String) {
        let row = Self.row(Self.reading(state))
        #expect(row.state == word)
        #expect(row.since == nil)
        #expect(row.open == true)
        #expect(row.moving)
        #expect(row.action == .stop)
        #expect(alarmDoorStatusLines(state: row.state, since: row.since, stale: row.stale) == [word])
    }

    @Test("A garage that cannot stop offers no Stop while moving", arguments: ["3", "true", "null"])
    func movingWithoutStopSupport(features: String) {
        let row = Self.row(Self.reading("opening", features: features))
        #expect(row.state == "Opening…")
        #expect(row.action == nil)
    }

    @Test("A garage with no feature mask keeps its Stop, as the Doors card did")
    func movingWithMissingMask() {
        #expect(Self.row(Self.reading("closing", features: nil)).action == .stop)
    }

    @Test("An unavailable or unknown garage has no button", arguments: ["unavailable", "unknown"])
    func unavailable(state: String) {
        let row = Self.row(Self.reading(state))
        #expect(row.state == "Unavailable")
        #expect(row.since == nil)
        #expect(row.open == nil)
        #expect(row.action == nil)
        #expect(!row.stale)
    }

    @Test("Before any reading the row is a dash, never a guessed state")
    func noReadingYet() {
        let row = Self.row(nil)
        #expect(row.name == "Garage")
        #expect(row.state == "—")
        #expect(row.action == nil)
        #expect(row.open == nil)
    }

    @Test("A failed first read is Unavailable with no button")
    func firstFailure() {
        let row = Self.row(nil, error: "Can't reach Home Assistant")
        #expect(row.state == "Unavailable")
        #expect(row.action == nil)
        #expect(!row.stale)
        #expect(row.error == "Can't reach Home Assistant")
    }

    @Test("Offline shows the last known state and when it was checked, with no button")
    func lastKnown() {
        let row = Self.row(Self.reading("closed"), error: "Can't reach Home Assistant")
        #expect(row.state == "Closed")
        #expect(row.stale)
        #expect(row.since == "Last checked 9:41 AM")
        #expect(row.action == nil)
        #expect(row.open == false)
        #expect(alarmDoorStatusLines(state: row.state, since: row.since, stale: row.stale)
            == ["Closed · 9:41 AM", "Closed"])
    }

    @Test("A cover that is not a garage or gate, or the wrong entity, is never read as the garage")
    func wrongEntity() {
        let blind = HaStateReading(entityID: Self.garageID,
            json: Self.garageJSON("closed", deviceClass: "blind"), checkedAt: Self.checked)
        let other = HaStateReading(entityID: Self.garageID,
            json: Self.garageJSON("closed", id: "cover.other"), checkedAt: Self.checked)
        for reading in [blind, other] {
            let row = Self.row(reading)
            #expect(row.state == "Unavailable")
            #expect(row.action == nil)
            #expect(row.error != nil)
        }
    }

    @Test("The lock row's one-line status drops words before it drops the state")
    func lockStatusLines() {
        #expect(alarmDoorStatusLines(state: "Locked", since: "since 7:44 PM", stale: false)
            == ["Locked · since 7:44 PM", "Locked · 7:44 PM", "Locked"])
        #expect(alarmDoorStatusLines(state: "Locked", since: "Last checked 7:44 PM", stale: true)
            == ["Locked · 7:44 PM", "Locked"])
        #expect(alarmDoorStatusLines(state: "Choose in Settings", since: nil, stale: false) == ["Choose in Settings"])
    }

    // MARK: Through the alarm snapshot

    private static func panelReading() -> HaStateReading {
        HaStateReading(entityID: panelID, json: #"{"entity_id":"\#(panelID)","state":"armed_away","#
            + #""attributes":{"friendly_name":"Home Alarm","supported_features":3}}"#, checkedAt: checked)
    }
    private static func lockReading() -> HaStateReading {
        HaStateReading(entityID: lockID, json: #"{"entity_id":"\#(lockID)","state":"locked","#
            + #""attributes":{"friendly_name":"Front Door"}}"#, checkedAt: checked)
    }
    private static func config(garage: String? = garageID) -> HaConfig {
        HaConfig(baseUrl: "https://home.example", token: "fixture", entityId: panelID, lockId: lockID,
                 lockName: "Front Door", garageId: garage)
    }
    private static func context(garage state: String = "closed", operation: DoorOperation? = nil,
                                failures: [String: HaStateFailure] = [:], config: HaConfig = config()) -> HaStoreSnapshot {
        HaStoreSnapshot(config: config, scope: "scope",
            readings: [panelID: panelReading(), lockID: lockReading(), garageID: reading(state)],
            alarmRevision: "alarm-rev", failures: failures, doorOperation: operation, doorActionRevision: "door-rev")
    }
    private static func stored(_ context: HaStoreSnapshot) -> AlarmSnapshot {
        alarmStoredSnapshot(context, now: now, zone: zone, locale: locale)
    }

    @Test("No garage configured: no row, and the single-row layout stays")
    func noGarageConfigured() {
        let snapshot = Self.stored(Self.context(config: Self.config(garage: nil)))
        #expect(snapshot.garage == nil)
        #expect(!snapshot.compactDoorRows)
    }

    @Test("The row carries the door-command origin, separate from the alarm's")
    func rowCarriesDoorOrigin() throws {
        let snapshot = Self.stored(Self.context())
        let garage = try #require(snapshot.garage)
        #expect(snapshot.compactDoorRows)
        #expect(garage.entityID == Self.garageID)
        #expect(garage.actionRevision == "door-rev")
        #expect(snapshot.alarmRevision == "alarm-rev")
        #expect(snapshot.requestScope == "scope")
        #expect(garage.action == .open)
        #expect(garage.replacingOperation.isEmpty)
    }

    @Test("An armed alarm with the garage open leaves the rail as it is for an unlocked front door")
    func railIgnoresOpenGarage() throws {
        let open = Self.stored(Self.context(garage: "open"))
        let closed = Self.stored(Self.context(garage: "closed"))
        #expect(try #require(open.garage).open == true)
        #expect(open.stateWord == closed.stateWord)
        #expect(open.detail == closed.detail)
        #expect(open.tone == closed.tone)
        #expect(open.glyph == closed.glyph)
        #expect(open.commandFeedback == nil)
    }

    @Test("A pending Open or Close reads as moving and offers only its own Stop",
          arguments: [("open", "Opening…"), ("close", "Closing…")])
    func pendingCommand(action: String, word: String) throws {
        let operation = DoorOperation(id: "op-1", entityID: Self.garageID, action: action, startedAt: Self.now)
        let garage = try #require(Self.stored(Self.context(operation: operation)).garage)
        #expect(garage.pending)
        #expect(garage.moving)
        #expect(garage.state == word)
        #expect(garage.since == nil)
        #expect(garage.action == .stop)
        #expect(garage.replacingOperation == "op-1")
    }

    @Test("A pending Stop offers nothing more")
    func pendingStop() throws {
        let operation = DoorOperation(id: "op-2", entityID: Self.garageID, action: "stop", startedAt: Self.now)
        let garage = try #require(Self.stored(Self.context(garage: "opening", operation: operation)).garage)
        #expect(garage.state == "Stopping…")
        #expect(garage.action == nil)
        #expect(garage.replacingOperation.isEmpty)
    }

    @Test("A pending command on a garage that cannot stop offers no Stop")
    func pendingWithoutStopSupport() throws {
        var context = Self.context(operation: DoorOperation(id: "op-3", entityID: Self.garageID, action: "open",
                                                            startedAt: Self.now))
        context = HaStoreSnapshot(config: context.config, scope: context.scope,
            readings: context.readings.merging([Self.garageID: Self.reading("closed", features: "3")]) { $1 },
            alarmRevision: context.alarmRevision, doorOperation: context.doorOperation,
            doorActionRevision: context.doorActionRevision)
        let garage = try #require(Self.stored(context).garage)
        #expect(garage.state == "Opening…")
        #expect(garage.action == nil)
    }

    @Test("Another door's pending command makes the garage button inert")
    func otherDoorPending() throws {
        let operation = DoorOperation(entityID: "lock.side", action: "lock", startedAt: Self.now)
        let garage = try #require(Self.stored(Self.context(operation: operation)).garage)
        #expect(garage.state == "Closed")
        #expect(!garage.pending)
        #expect(garage.action == nil)
    }

    // MARK: A failed command

    private static let commandEnded = checked.addingTimeInterval(60)
    private static func failedOperation(_ action: String = "open",
                                        error: String = "Couldn't confirm · Refresh to check") -> DoorOperation {
        DoorOperation(entityID: garageID, action: action, startedAt: checked, endedAt: commandEnded,
                      error: error, delivered: true)
    }

    @Test("A failed command says why in the status line and keeps the button, until a newer reading")
    func failedCommand() throws {
        let failed = Self.failedOperation()
        let garage = try #require(Self.stored(Self.context(operation: failed)).garage)
        #expect(garage.stale)
        #expect(garage.action == .open)
        #expect(garage.actionRevision == "door-rev")
        #expect(garage.error == "Couldn't confirm · Refresh to check")
        #expect(garage.commandNotice == "Couldn't open · try again")
        #expect(alarmGarageStatusLines(garage) == ["Couldn't open · try again", "Couldn't open"])

        var context = Self.context(operation: failed)
        context = HaStoreSnapshot(config: context.config, scope: context.scope,
            readings: context.readings.merging([Self.garageID: Self.reading("closed", at: Self.commandEnded.addingTimeInterval(1))]) { $1 },
            alarmRevision: context.alarmRevision, doorOperation: failed, doorActionRevision: context.doorActionRevision)
        let refreshed = try #require(Self.stored(context).garage)
        #expect(!refreshed.stale)
        #expect(refreshed.action == .open)
        #expect(refreshed.error == nil)
        #expect(refreshed.commandNotice == nil)
        #expect(alarmGarageStatusLines(refreshed) == ["Closed · since 9:20 AM", "Closed · 9:20 AM", "Closed"])
    }

    @Test("The reason names the command that failed and the retry is the row's own button", arguments: [
        ("open", "closed", "Couldn't open · try again", DoorAction.open),
        ("close", "open", "Couldn't close · try again", DoorAction.close),
        ("stop", "opening", "Couldn't stop · try again", DoorAction.stop),
    ])
    func failedCommandNamesTheAction(action: String, state: String, line: String, retry: DoorAction) throws {
        let context = Self.context(garage: state, operation: Self.failedOperation(action, error: "Can't reach Home Assistant"))
        let garage = try #require(Self.stored(context).garage)
        #expect(garage.action == retry)
        #expect(alarmGarageStatusLines(garage).first == line)
        #expect(garage.error == "Can't reach Home Assistant")
    }

    @Test("A command refused for sign-in or setup points there instead of offering a retry", arguments: [
        ("Signed out: sign in again", "Couldn't open · sign in"),
        ("Not found: check the entity", "Couldn't open · check Settings"),
    ])
    func failedCommandNeedingSetup(error: String, line: String) throws {
        let garage = try #require(Self.stored(Self.context(operation: Self.failedOperation(error: error))).garage)
        #expect(garage.action == nil)
        #expect(garage.error == error)
        #expect(alarmGarageStatusLines(garage) == [line, "Couldn't open"])
    }

    @Test("With the reading failed too there is no button, and the line says to refresh")
    func failedCommandAndFailedRead() throws {
        let failure = HaStateFailure(message: "Can't reach Home Assistant", checkedAt: Self.now, reason: .transport)
        let context = Self.context(operation: Self.failedOperation(), failures: [Self.garageID: failure])
        let garage = try #require(Self.stored(context).garage)
        #expect(garage.stale)
        #expect(garage.action == nil)
        #expect(alarmGarageStatusLines(garage) == ["Couldn't open · refresh to check", "Couldn't open"])
    }

    @Test("A failed command on a garage with no reading stays Unavailable with no button")
    func failedCommandWithoutReading() throws {
        let context = HaStoreSnapshot(config: Self.config(), scope: "scope",
            readings: [Self.panelID: Self.panelReading(), Self.lockID: Self.lockReading()],
            doorOperation: Self.failedOperation(), doorActionRevision: "door-rev")
        let garage = try #require(Self.stored(context).garage)
        #expect(garage.state == "Unavailable")
        #expect(garage.action == nil)
        #expect(alarmGarageStatusLines(garage) == ["Couldn't open · refresh to check", "Couldn't open"])
    }

    @Test("A retry in flight replaces the reason with the command's progress")
    func retryInFlight() throws {
        let retry = DoorOperation(entityID: Self.garageID, action: "open", startedAt: Self.commandEnded.addingTimeInterval(5))
        let garage = try #require(Self.stored(Self.context(operation: retry)).garage)
        #expect(garage.pending)
        #expect(garage.commandNotice == nil)
        #expect(alarmGarageStatusLines(garage) == ["Opening…"])
    }

    @Test("Another door's failed command leaves the garage row alone")
    func otherDoorsFailure() throws {
        let other = DoorOperation(entityID: "cover.side_gate", action: "open", startedAt: Self.checked,
            endedAt: Self.commandEnded, error: "Couldn't confirm · Refresh to check", delivered: true)
        let garage = try #require(Self.stored(Self.context(operation: other)).garage)
        #expect(garage.commandNotice == nil)
        #expect(garage.error == nil)
        #expect(garage.action == .open)
    }

    @Test("A row saved before the reason existed still decodes, with no reason")
    func decodesOlderRow() throws {
        let older = #"{"entityID":"cover.garage","name":"Garage","state":"Closed","moving":false,"stale":false,"#
            + #""pending":false,"actionRevision":"","replacingOperation":""}"#
        let row = try JSONDecoder().decode(AlarmGarageRow.self, from: Data(older.utf8))
        #expect(row.commandNotice == nil)
        #expect(alarmGarageStatusLines(row) == ["Closed"])
    }

    @Test("A confirmed command leaves no trace on the row")
    func confirmedCommand() throws {
        let done = DoorOperation(entityID: Self.garageID, action: "open", startedAt: Self.checked,
            endedAt: Self.checked.addingTimeInterval(20), delivered: true)
        let garage = try #require(Self.stored(Self.context(garage: "open", operation: done)).garage)
        #expect(garage.state == "Open")
        #expect(garage.action == .close)
        #expect(!garage.pending)
    }

    @Test("A stored read failure shows the garage last-known beside a last-known lock")
    func offlineIsConsistentWithLockRow() throws {
        let failure = HaStateFailure(message: "Can't reach Home Assistant", checkedAt: Self.now, reason: .transport)
        let snapshot = Self.stored(Self.context(failures: [Self.panelID: failure, Self.lockID: failure,
                                                             Self.garageID: failure]))
        let garage = try #require(snapshot.garage)
        #expect(snapshot.doorStale)
        #expect(garage.stale)
        #expect(snapshot.doorAction == nil)
        #expect(garage.action == nil)
        #expect(snapshot.doorSince == "Last checked 9:41 AM")
        #expect(garage.since == "Last checked 9:41 AM")
    }

    @Test("An old cached garage reading is last-known even without a new failure")
    func oldCacheIsLastKnown() throws {
        let old = Self.reading("closed", at: Self.now.addingTimeInterval(-16 * 60))
        let context = HaStoreSnapshot(config: Self.config(), scope: "scope",
            readings: [Self.panelID: Self.panelReading(), Self.lockID: Self.lockReading(), Self.garageID: old],
            doorActionRevision: "door-rev")
        let garage = try #require(Self.stored(context).garage)
        #expect(garage.stale)
        #expect(garage.action == nil)
    }

    @Test("A transient save error marks the garage last-known with the lock")
    func transientErrorCoversGarage() throws {
        let snapshot = alarmStoredSnapshot(Self.context(), now: Self.now,
            transientError: "Can't save readings · Refresh to retry", zone: Self.zone, locale: Self.locale)
        #expect(snapshot.doorStale)
        #expect(try #require(snapshot.garage).stale)
    }

    @Test("Setup shows no garage row")
    func setupHasNoGarage() {
        let context = HaStoreSnapshot(config: nil, scope: "scope")
        #expect(Self.stored(context).garage == nil)
    }

    @Test("A snapshot saved before the garage row still decodes")
    func oldSnapshotDecodes() throws {
        var encoded = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AlarmSnapshot.sample)) as? [String: Any])
        encoded.removeValue(forKey: "garage")
        let decoded = try JSONDecoder().decode(AlarmSnapshot.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(decoded.garage == nil)
        #expect(decoded.doorName == "Front Door")
    }
}
