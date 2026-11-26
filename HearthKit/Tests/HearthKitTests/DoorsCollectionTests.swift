import XCTest
@testable import HearthKit

final class DoorsCollectionTests: XCTestCase {
    func testPendingOpenCloseStopAndLockCannotPresentCalmAllShut() {
        let observed = doorsSummary([
            Door(id: "cover.garage", name: "Garage", kind: .garage, state: "closed",
                since: now.addingTimeInterval(-60), checkedAt: now),
            Door(id: "lock.front", name: "Front Door", kind: .lock, state: "locked",
                since: now.addingTimeInterval(-60), checkedAt: now),
        ], now: now)
        XCTAssertEqual(observed.headline, "All shut")
        XCTAssertEqual(observed.tone, .calm)
        for action in [DoorAction.open, .close, .stop, .lock] {
            let operation = DoorOperation(entityID: action == .lock ? "lock.front" : "cover.garage",
                action: action.rawValue, startedAt: now, delivered: true)
            let shown = doorsCommandPresentation(observed, operation: operation)
            XCTAssertEqual(shown.headline, "Updating doors…", action.rawValue)
            XCTAssertEqual(shown.tone, .unknown, action.rawValue)
            XCTAssertEqual(shown.rows, observed.rows)
            XCTAssertEqual(shown.lockLine, observed.lockLine)
        }
    }

    func testPendingHeadingPreservesKnownOpenWarningsAlertAndMissingTelemetry() {
        let examples: [(Door, DoorsTone)] = [
            (Door(id: "cover.garage", name: "Garage", kind: .garage, state: "open",
                since: now.addingTimeInterval(-60)), .warn),
            (Door(id: "cover.garage", name: "Garage", kind: .garage, state: "open",
                since: now.addingTimeInterval(-3600)), .alert),
            (Door(id: "cover.garage", name: "Garage", kind: .garage, state: "unknown", since: nil), .unknown),
        ]
        for (door, tone) in examples {
            let observed = doorsSummary([door], now: now)
            XCTAssertEqual(observed.tone, tone)
            let operation = DoorOperation(entityID: door.id, action: "close", startedAt: now)
            let shown = doorsCommandPresentation(observed, operation: operation)
            XCTAssertEqual(shown.headline, "Updating doors…")
            XCTAssertEqual(shown.tone, tone)
            XCTAssertEqual(shown.rows, observed.rows)
            XCTAssertEqual(shown.lockLine, observed.lockLine)
        }
    }

    func testNoCompletedOrFailedCommandRetainsObservedPresentation() {
        let observed = doorsSummary([
            Door(id: "cover.garage", name: "Garage", kind: .garage, state: "closed", since: nil, checkedAt: now),
        ], now: now)
        XCTAssertEqual(doorsCommandPresentation(observed, operation: nil), observed)
        let unsupported = DoorOperation(entityID: "cover.garage", action: "not_an_action", startedAt: now)
        XCTAssertEqual(doorsCommandPresentation(observed, operation: unsupported), observed)
        for error in [nil, "Could not confirm"] as [String?] {
            let operation = DoorOperation(entityID: "cover.garage", action: "open",
                startedAt: now.addingTimeInterval(-30), endedAt: now, error: error, delivered: true)
            XCTAssertEqual(doorsCommandPresentation(observed, operation: operation), observed)
        }
    }

    func testLargestSupportedTypeKeepsEverySafetyCountInsideMinimumSize() {
        let rows = [
            DoorView(id: "cover.open", name: "Garage", status: "Open", open: true, action: .close),
            DoorView(id: "cover.missing", name: "Gate", status: "No reading", open: nil, action: nil),
            DoorView(id: "lock.front", name: "Front", status: "Locked", open: false, action: nil),
        ]
        for scale in [2.0, 2.24] {
            let layout = doorsCollectionLayout(width: 220, height: 110, fontScale: scale, rows: rows, hasError: true)
            XCTAssertTrue(layout.fits)
            XCTAssertGreaterThanOrEqual(layout.fontSize, 12 * scale)
            let text = layout.lines.joined(separator: " ")
            XCTAssertTrue(text.contains("1 open"))
            XCTAssertTrue(text.contains("1 shut"))
            XCTAssertTrue(text.contains("1 N/A") || text.contains("1 unavailable"))
            let actual = Double(layout.lines.count) * layout.lineHeight + Double(layout.lines.count - 1) * 4
            XCTAssertLessThanOrEqual(actual + 2 * layout.budget.padding, 110)
            XCTAssertLessThanOrEqual(layout.contentWidth + 2 * layout.budget.padding, 220)
        }
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var config: HaConfig {
        HaConfig(baseUrl: "https://example.test", token: "fixture", entityId: "",
                 doorIdsJson: #"["cover.east","lock.front"]"#, doorsChosen: true)
    }
    private func state(_ id: String, _ state: String, _ deviceClass: String?, _ name: String) -> String {
        #"{"entity_id":"\#(id)","state":"\#(state)","attributes":{"friendly_name":"\#(name)","device_class":\#(deviceClass.map { "\"\($0)\"" } ?? "null")}}"#
    }
    private func reading(_ id: String, _ value: String, _ deviceClass: String?, _ name: String, at: Date? = nil) -> HaStateReading {
        HaStateReading(entityID: id, json: state(id, value, deviceClass, name), checkedAt: at ?? now)
    }

    func testMissingGarageNeverDisappearsBesideFreshLockedDoor() {
        let snapshot = mapDoorsSnapshot(config: config,
            readings: ["lock.front": reading("lock.front", "locked", nil, "Front Door")], errors: [:], now: now)
        XCTAssertEqual(snapshot.doors.map(\.id), ["cover.east", "lock.front"])
        XCTAssertEqual(snapshot.summary.headline, "1 not reporting")
        XCTAssertEqual(snapshot.summary.tone, .unknown)
        XCTAssertNil(snapshot.summary.rows.first?.action)
    }

    func testCachedFailureRetainsSuccessfulTimeAndSuppressesActions() async {
        let old = now.addingTimeInterval(-600)
        let cache = ["cover.east": reading("cover.east", "closed", "garage", "East Garage", at: old)]
        var single = config
        single.doorIdsJson = #"["cover.east"]"#
        let snapshot = await fetchDoorsSnapshot(single, previous: cache, now: now) { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertEqual(snapshot.observedAt, old)
        XCTAssertEqual(snapshot.doors.first?.checkedAt, old)
        XCTAssertNotNil(snapshot.error)
        XCTAssertTrue(snapshot.summary.rows.first?.status.hasPrefix("Last known") == true)
        XCTAssertNil(snapshot.summary.rows.first?.action)
        XCTAssertNil(snapshot.summary.rows.first?.open)
        XCTAssertEqual(snapshot.summary.tone, .unknown)
    }

    func testWrongRequestedIdentityAndMalformedStateNeverGetSuccessfulTimestamp() async {
        for reply in [#"{"entity_id":"cover.other","state":"closed","attributes":{"device_class":"garage"}}"#,
                      #"{"entity_id":"cover.east","state":true,"attributes":{"device_class":"garage"}}"#, "{}"] {
            let snapshot = await fetchDoorsSnapshot(config, now: now) { _ in reply }
            XCTAssertEqual(snapshot.doors.map(\.id), ["cover.east", "lock.front"])
            XCTAssertEqual(snapshot.state, .failed)
            XCTAssertNil(snapshot.observedAt)
            XCTAssertEqual(snapshot.checkedAt, "")
            XCTAssertTrue(snapshot.summary.rows.allSatisfy { $0.open == nil && $0.action == nil })
        }
    }

    func testFreshUnknownReplacesClosedCacheWithoutBorrowedAction() async {
        var single = config
        single.doorIdsJson = #"["cover.east"]"#
        let cached = ["cover.east": reading("cover.east", "closed", "garage", "East Garage", at: now.addingTimeInterval(-60))]
        let reply = state("cover.east", "unknown", "garage", "East Garage")
        let snapshot = await fetchDoorsSnapshot(single, previous: cached, now: now) { _ in reply }
        XCTAssertEqual(snapshot.doors.first?.state, "unknown")
        XCTAssertEqual(snapshot.observedAt, now)
        XCTAssertNil(snapshot.doors.first?.error)
        XCTAssertNil(snapshot.summary.rows.first?.action)
        XCTAssertEqual(snapshot.summary.tone, .unknown)
    }

    func testSetupAndIntentionalEmptyNeverFetchOrShowSample() async {
        let setup = await fetchDoorsSnapshot(nil, now: now) { _ in XCTFail("Setup requested an entity"); return "{}" }
        XCTAssertEqual(setup.state, .setup)
        XCTAssertTrue(setup.summary.rows.isEmpty)
        XCTAssertNil(setup.observedAt)
        var empty = config
        empty.doorIdsJson = "[]"
        empty.lockId = "lock.front"
        let snapshot = await fetchDoorsSnapshot(empty, now: now) { _ in XCTFail("Intentional empty requested an entity"); return "{}" }
        XCTAssertEqual(snapshot.state, .empty)
        XCTAssertTrue(snapshot.summary.rows.isEmpty)
    }

    func testStopRequiresKnownOpenOrClosedPosition() {
        for state in ["unknown", "unavailable", "opening", "closing", "jammed", ""] {
            XCTAssertFalse(DoorAction.stop.done(state), state)
        }
        XCTAssertFalse(DoorAction.stop.done(nil))
        XCTAssertTrue(DoorAction.stop.done("closed"))
        XCTAssertTrue(DoorAction.stop.done("open"))
    }

    func testRowBudgetScalesGeometryAndPreservesOverflow() {
        let small = doorsRowBudget(height: 180, fontScale: 1, rowCount: 12)
        let tall = doorsRowBudget(height: 600, fontScale: 1, rowCount: 12)
        XCTAssertEqual(small.count, 1)
        XCTAssertTrue(small.showOverflow)
        XCTAssertGreaterThan(tall.count, small.count)
        let normal = doorsRowBudget(height: 310, fontScale: 1, rowCount: 8)
        let large = doorsRowBudget(height: 310, fontScale: 1.6, rowCount: 8, hasError: true)
        XCTAssertGreaterThanOrEqual(large.rowHeight, 86)
        XCTAssertLessThan(large.count, normal.count)
        XCTAssertLessThanOrEqual(large.contentHeight, 310 - 30)
        XCTAssertEqual(doorsRowBudget(height: 20, fontScale: 1, rowCount: 8).count, 0)
    }

    func testShortCardsAlwaysRetainTheHiddenSelectedCounts() {
        for (height, scale, hasError) in [(110.0, 1.0, false), (170.0, 1.6, false), (340.0, 3.0, true)] {
            let layout = doorsRowBudget(height: height, fontScale: scale, rowCount: 8, hasError: hasError)
            XCTAssertTrue(layout.showOverflow, "Selected counts disappear at height \(height) and scale \(scale)")
        }
    }

    func testCompactCountsUseBoundedRealHeightAndWidthAtLargeType() {
        let rows = [
            DoorView(id: "cover.open", name: "Garage", status: "Open", open: true, action: .close),
            DoorView(id: "cover.missing", name: "Gate", status: "No reading", open: nil, action: nil),
            DoorView(id: "lock.front", name: "Front", status: "Locked", open: false, action: nil),
        ]
        for (width, height, scale) in [(220.0, 110.0, 1.6), (220.0, 170.0, 1.6), (320.0, 340.0, 3.0)] {
            let layout = doorsCollectionLayout(width: width, height: height, fontScale: scale, rows: rows, hasError: true)
            XCTAssertTrue(layout.budget.summaryOnly)
            XCTAssertTrue(layout.fits)
            XCTAssertEqual(layout.groups, ["1 open", "1 unavailable", "1 shut"])
            XCTAssertFalse(layout.lines.isEmpty)
            for group in layout.groups { XCTAssertTrue(layout.lines.joined(separator: " ").contains(group)) }
            XCTAssertGreaterThanOrEqual(layout.fontSize, 14 * scale)
            let actualHeight = Double(layout.lines.count) * layout.lineHeight + Double(layout.lines.count - 1) * 4
            XCTAssertEqual(layout.budget.contentHeight, actualHeight, accuracy: 0.01)
            XCTAssertLessThanOrEqual(actualHeight + 2 * layout.budget.padding, height)
            XCTAssertLessThanOrEqual(layout.contentWidth + 2 * layout.budget.padding, width)
        }
    }

    func testOverflowCountsEveryRemainingSafetyGroup() {
        XCTAssertEqual(doorsOverflowLine([
            DoorView(id: "cover.open", name: "Garage", status: "Open", open: true, action: .close),
            DoorView(id: "cover.missing", name: "Gate", status: "No reading", open: nil, action: nil),
            DoorView(id: "lock.front", name: "Front", status: "Locked", open: false, action: nil),
        ]), "1 open · 1 unavailable · 1 shut")
    }

    func testPriorityGroupsPreserveSelectionOrder() {
        var chosen = config
        chosen.doorIdsJson = #"["lock.front","cover.east","binary_sensor.side","cover.west","binary_sensor.back"]"#
        let snapshot = mapDoorsSnapshot(config: chosen, readings: [
            "lock.front": reading("lock.front", "locked", nil, "Front"),
            "cover.east": reading("cover.east", "open", "garage", "East"),
            "cover.west": reading("cover.west", "open", "garage", "West"),
            "binary_sensor.back": reading("binary_sensor.back", "off", "door", "Back"),
        ], errors: [:], now: now)
        XCTAssertEqual(snapshot.summary.rows.map(\.id),
            ["cover.east", "cover.west", "binary_sensor.side", "lock.front", "binary_sensor.back"])
    }

    func testLegacyCachedFailureLabelsHistoryWithoutInventingTime() {
        let view = doorView(Door(id: "cover.east", name: "East Garage", kind: .garage,
            state: "closed", since: nil, error: "Offline"), now: now)
        XCTAssertTrue(view.status.hasPrefix("Last known"))
        XCTAssertNil(view.action)
        XCTAssertNil(view.open)
    }
}
