import XCTest
@testable import HearthKit

final class DoorsCompactStopLayoutTests: XCTestCase {
    private let rows = [
        DoorView(id: "cover.garage", name: "Garage", status: "Opening…", open: true, action: .stop),
        DoorView(id: "cover.side_gate", name: "Side Gate", status: "Open", open: true, action: .close),
        DoorView(id: "lock.front", name: "Front", status: "Locked", open: false, action: nil),
        DoorView(id: "binary_sensor.back", name: "Back", status: "Closed", open: false, action: nil),
    ]
    func testCompactOwnedStopKeepsItsExactIdentityAheadOfRemainingSafetyCounts() {
        let layout = doorsCollectionLayout(width: 350, height: 164, fontScale: 1, rows: rows, priorityID: "cover.garage")
        XCTAssertEqual(layout.priorityID, "cover.garage")
        XCTAssertFalse(layout.budget.summaryOnly)
        XCTAssertEqual(layout.budget.count, 1)
        XCTAssertEqual(layout.budget.headerHeight, 0)
        XCTAssertEqual(layout.groups, ["1 open", "2 shut"])
        XCTAssertTrue(layout.fits)
        XCTAssertLessThanOrEqual(layout.budget.contentHeight + 2 * layout.budget.padding, 164)
    }
    func testPartialFitCannotHideAnOwnedStopBehindAnEarlierRow() {
        let allOpen = (0..<4).map {
            DoorView(id: "cover.gate_\($0)", name: "Gate \($0)", status: "Open", open: true, action: .close)
        }
        let layout = doorsCollectionLayout(width: 350, height: 164, fontScale: 1,
            rows: allOpen, priorityID: "cover.gate_1")
        XCTAssertEqual(layout.priorityID, "cover.gate_1")
        XCTAssertEqual(layout.budget.count, 1)
        XCTAssertEqual(layout.groups, ["3 open"])
        XCTAssertTrue(layout.fits)
        XCTAssertLessThanOrEqual(layout.budget.contentHeight + 2 * layout.budget.padding, 164)
    }
    func testImpossibleSizeOrForeignPriorityKeepsHonestCountsWithoutAControl() {
        for (scale, id) in [(2.24, "cover.garage"), (1.0, "cover.not_selected")] {
            let layout = doorsCollectionLayout(width: 220, height: 110, fontScale: scale, rows: rows, priorityID: id)
            XCTAssertNil(layout.priorityID)
            XCTAssertTrue(layout.budget.summaryOnly)
            XCTAssertEqual(layout.groups, ["2 open", "2 shut"])
            XCTAssertTrue(layout.fits)
        }
    }
    func testStopCapabilityPreservesMissingVersusUnsupportedAndMalformedRawThroughHistoricalSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let config = HaConfig(baseUrl: "https://home.example", token: "fixture", entityId: "",
            doorIdsJson: #"["cover.garage"]"#, doorsChosen: true)
        for (raw, expected) in [(nil, nil), ("8", true), ("3", false), ("true", false),
                                ("null", false), (#""8""#, false), ("-1", false), ("1.5", false)] as [(String?, Bool?)] {
            let mask = raw.map { #","supported_features":\#($0)"# } ?? ""
            let json = #"{"entity_id":"cover.garage","state":"unknown","attributes":{"device_class":"garage"\#(mask)}}"#
            let reading = HaStateReading(entityID: "cover.garage", json: json, checkedAt: now)
            let snapshot = mapDoorsSnapshot(config: config, readings: ["cover.garage": reading],
                errors: ["cover.garage": "Delivery uncertain"], now: now)
            XCTAssertEqual(try XCTUnwrap(snapshot.doors.first).supportsStop, expected)
        }
    }
}
