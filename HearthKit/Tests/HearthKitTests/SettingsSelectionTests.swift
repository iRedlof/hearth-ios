import XCTest
@testable import HearthKit

final class SettingsSelectionTests: XCTestCase {
    func testAddingDiscoveredItemPreservesMissingSavedItemAndOrder() {
        let result = selectionAfterToggle(["missing", "A"], id: "B", available: ["B", "A"], limit: nil)
        XCTAssertEqual(result.ids, ["missing", "A", "B"])
        XCTAssertFalse(result.blockedByLimit)
    }

    func testMissingSavedItemCanBeExplicitlyRemoved() {
        let result = selectionAfterToggle(["missing", "A"], id: "missing", available: ["A"], limit: nil)
        XCTAssertEqual(result.ids, ["A"])
        XCTAssertFalse(result.blockedByLimit)
    }

    func testLastDeselectionStaysEmpty() {
        let result = selectionAfterToggle(["A"], id: "A", available: ["A", "B"], limit: 6)
        XCTAssertEqual(result.ids, [])
        XCTAssertFalse(result.blockedByLimit)
    }

    func testQuickAndFavouritesRejectExtraAdditionWithoutDeletingExistingSelection() {
        let quick = ["A", "B", "C", "D", "E", "F"]
        let favourite = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        let blockedQuick = selectionAfterToggle(quick, id: "G", available: quick + ["G"], limit: 6)
        let blockedFavourite = selectionAfterToggle(favourite, id: "M", available: favourite + ["M"], limit: 12)
        XCTAssertEqual(blockedQuick.ids, quick)
        XCTAssertTrue(blockedQuick.blockedByLimit)
        XCTAssertEqual(blockedFavourite.ids, favourite)
        XCTAssertTrue(blockedFavourite.blockedByLimit)
    }

    func testLegacyOverLimitSelectionIsPreservedUntilExplicitRemoval() {
        let legacy = ["missing", "A", "B", "C", "D", "E", "F", "G"]
        let blocked = selectionAfterToggle(legacy, id: "H", available: ["A", "B", "H"], limit: 6)
        XCTAssertEqual(blocked.ids, legacy)
        XCTAssertTrue(blocked.blockedByLimit)
        let removed = selectionAfterToggle(legacy, id: "B", available: ["A", "B", "H"], limit: 6)
        XCTAssertEqual(removed.ids, ["missing", "A", "C", "D", "E", "F", "G"])
        XCTAssertFalse(removed.blockedByLimit)
    }

    func testAdditionBelowLimitKeepsSavedOrderAndIgnoresDuplicateDiscovery() {
        let result = selectionAfterToggle(["B", "A"], id: "C", available: ["A", "C", "C", "B"], limit: 6)
        XCTAssertEqual(result.ids, ["B", "A", "C"])
        XCTAssertFalse(result.blockedByLimit)
    }
}
