import XCTest
@testable import HearthKit

final class DoorRowIdentityTests: XCTestCase {
    private func rows(_ names: [String]) -> [DoorView] {
        names.enumerated().map { index, name in
            DoorView(id: index == 0 ? "cover.garage" : "cover.side_gate", name: name,
                status: "Closed · since 9:00 AM", open: false, action: .open)
        }
    }
    func testIdenticalAndTruncationCollidingNamesExposeDistinctMatchingEntityLabels() {
        for names in [["Upstairs entrance", "Upstairs entrance"],
                      ["Upstairs entrance east", "Upstairs entrance west"]] {
            let values = rows(names)
            let identities = doorRowIdentities(values, nameCapacity: 12, detailCapacity: 30)
            XCTAssertEqual(identities["cover.garage"]?.label, "garage")
            XCTAssertEqual(identities["cover.side_gate"]?.label, "side gate")
            XCTAssertTrue(identities.values.allSatisfy(\.identifiable))
            XCTAssertEqual(identities, doorRowIdentities(Array(values.reversed()), nameCapacity: 12, detailCapacity: 30))
        }
    }
    func testActionIsInertWhenItsDistinctLabelCannotFitAndNoncollidingNamesStayUnchanged() {
        let identities = doorRowIdentities(rows(["Same name", "Same name"]), nameCapacity: 4, detailCapacity: 4)
        XCTAssertFalse(identities["cover.garage"]!.identifiable)
        XCTAssertFalse(identities["cover.side_gate"]!.identifiable)
        XCTAssertTrue(doorRowIdentities(rows(["Garage", "Side Gate"]), nameCapacity: 12, detailCapacity: 30)
            .values.allSatisfy { $0.label == nil && $0.identifiable })
    }
}
