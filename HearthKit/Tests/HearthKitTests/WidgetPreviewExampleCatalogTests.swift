import XCTest
@testable import HearthKit

final class WidgetPreviewExampleCatalogTests: XCTestCase {
    func testKindRoundTripsKeepIndependentChoices() {
        var visit = WidgetPreviewExampleSelection()
        XCTAssertTrue(visit.select(id: "triggered", for: .alarm))
        XCTAssertTrue(visit.select(id: "one_pin", for: .lights))
        XCTAssertTrue(visit.select(id: "offer_last", for: .chargepoint))
        XCTAssertEqual(visit.selected(for: .alarm).id, "triggered")
        XCTAssertEqual(visit.selected(for: .lights).id, "one_pin")
        XCTAssertEqual(visit.selected(for: .chargepoint).id, "offer_last")
        XCTAssertEqual(visit.selected(for: .quick).id, "sample")
    }

    func testInvalidAndCrossKindChoiceCannotReplaceSelectedInput() {
        var visit = WidgetPreviewExampleSelection()
        XCTAssertTrue(visit.select(id: "armed_away", for: .alarm))
        XCTAssertFalse(visit.select(id: "not_an_example", for: .alarm))
        let car = visit.selected(for: .car)
        XCTAssertFalse(visit.select(car, for: .alarm))
        XCTAssertFalse(visit.select(id: "expired", for: .chargepoint))
        XCTAssertFalse(visit.select(id: "working_accept", for: .chargepoint))
        XCTAssertEqual(visit.selected(for: .alarm).id, "armed_away")
        XCTAssertEqual(visit.selected(for: .chargepoint).id, "heldSnoozeAvailable")
    }

    func testFamilyRoundTripRetainsSelectedConditionAndExistingMembership() {
        var visit = WidgetPreviewExampleSelection()
        XCTAssertTrue(visit.select(id: "auto_heating", for: .thermostat))
        for family in WidgetPreviewKind.thermostat.supportedFamilies {
            XCTAssertTrue([WidgetPreviewFamily.small, .medium, .large].contains(family))
            XCTAssertEqual(visit.selected(for: .thermostat).id, "auto_heating")
        }
        XCTAssertEqual(WidgetPreviewKind.lights.supportedFamilies, [.large])
        XCTAssertEqual(WidgetPreviewKind.chargepoint.supportedFamilies, [.medium])
    }

    func testEveryKindCanChooseAnAdmittedNonDefaultAndRetainItsDefaultInAnotherVisit() {
        for kind in WidgetPreviewKind.allCases {
            var first = WidgetPreviewExampleSelection()
            let untouched = WidgetPreviewExampleSelection()
            let initial = first.selected(for: kind)
            guard let nonDefault = widgetPreviewExamples(for: kind).first(where: { $0.id != initial.id }) else {
                XCTFail("No browsable condition for \(kind)"); continue
            }
            XCTAssertTrue(first.select(nonDefault, for: kind))
            XCTAssertEqual(first.selected(for: kind), nonDefault)
            XCTAssertEqual(untouched.selected(for: kind), initial)
        }
    }

    func testSelectionCopyIsIndependentAndChargePointConsumesSelectedMapper() {
        var first = WidgetPreviewExampleSelection()
        var second = first
        XCTAssertTrue(first.select(id: "offer_last", for: .chargepoint))
        XCTAssertTrue(second.select(id: "sessionExpiredSignInRequired", for: .chargepoint))
        let now = Date(timeIntervalSince1970: 1700000000)
        let firstCase = CpWidgetPreviewExample(rawValue: first.selected(for: .chargepoint).id)!
        let secondCase = CpWidgetPreviewExample(rawValue: second.selected(for: .chargepoint).id)!
        XCTAssertEqual(cpWidgetPreviewSnapshot(firstCase, now: now).keys.map(\.command), ["accept", "leave"])
        XCTAssertEqual(cpWidgetPreviewSnapshot(secondCase, now: now).bigAnswer, "Sign in")
        XCTAssertEqual(cpWidgetPreviewSnapshot(firstCase, now: now).account, "example")
        XCTAssertNil(cpWidgetPreviewSnapshot(firstCase, now: now).origin)
    }
    func testEverySelectableChargePointCaseResolvesARealInertProjection() {
        let now = Date(timeIntervalSince1970: 1700000000)
        for choice in widgetPreviewExamples(for: .chargepoint) {
            var visit = WidgetPreviewExampleSelection()
            XCTAssertTrue(visit.select(choice, for: .chargepoint))
            guard let example = CpWidgetPreviewExample(rawValue: visit.selected(for: .chargepoint).id) else {
                XCTFail("Selected case has no input mapper: \(choice.id)"); continue
            }
            let snapshot = cpWidgetPreviewSnapshot(example, now: now)
            XCTAssertFalse(snapshot.bigAnswer.isEmpty)
            XCTAssertNil(snapshot.origin)
            XCTAssertFalse(snapshot.working)
        }
    }

}
