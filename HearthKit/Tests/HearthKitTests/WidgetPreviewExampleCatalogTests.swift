import XCTest
@testable import HearthKit

final class WidgetPreviewExampleCatalogTests: XCTestCase {
    private func selectedAllOffSnapshot() -> LightsSnapshot {
        var visit = WidgetPreviewExampleSelection()
        visit.select(id: "all_off", for: .lights)
        return visit.selected(for: .lights).id == "sample" ? .sample :
            lightsAllOffWidgetPreviewSnapshot(now: Date(timeIntervalSince1970: 1_793_379_600))
    }

    func testAllOffSelectionConsumesSuccessfulZeroOnReading() {
        let snapshot = selectedAllOffSnapshot()
        XCTAssertEqual(snapshot.summary.headline, "All off")
        XCTAssertEqual(snapshot.summary.onCount, 0)
    }

    func testAllOffSelectionKeepsPorchOffExactlyOnce() {
        let page = lightTilePage(selectedAllOffSnapshot().summary)
        XCTAssertEqual(page.pinned.map(\.tile), ["Off"])
        XCTAssertTrue(page.main.isEmpty)
        XCTAssertEqual(page.hiddenCount, 0)
    }

    func testAllOffConsumedFactoryHasKnownMembershipAndSuccessfulInjectedTime() {
        let now = Date(timeIntervalSince1970: 1_793_379_600)
        let snapshot = lightsAllOffWidgetPreviewSnapshot(now: now)
        let summary = snapshot.summary
        let known = summary.off + summary.pinned
        XCTAssertEqual(Set(known.map(\.id)), Set((1...4).map { "light.fixture_\($0)" }))
        XCTAssertEqual(Set(known.map(\.name)), ["Kitchen", "Living room", "Desk lamp", "Porch"])
        XCTAssertTrue(known.allSatisfy { $0.available && !$0.on && $0.percent == nil && $0.rgb == nil && $0.status == "Off" })
        XCTAssertEqual(summary.offCount, 3)
        XCTAssertEqual(known.filter { $0.available && !$0.on }.count, 4)
        XCTAssertEqual(summary.pinned.map(\.id), ["light.fixture_4"])
        XCTAssertEqual(summary.pinned.map(\.name), ["Porch"])
        XCTAssertTrue(summary.off.allSatisfy { $0.id != "light.fixture_4" })
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertNil(snapshot.error)
        XCTAssertEqual(snapshot.checkedAt, widgetClock(now))
        let later = now.addingTimeInterval(3_600)
        XCTAssertEqual(lightsAllOffWidgetPreviewSnapshot(now: later).checkedAt, widgetClock(later))
        XCTAssertEqual(lightsAllOffWidgetPreviewSnapshot(now: later).summary, summary)
        XCTAssertEqual(snapshot, lightsAllOffWidgetPreviewSnapshot(now: now))
    }

    func testAllOffChoiceRetainsAcrossKindsAndCannotReplaceForeignOrIndependentDefaults() {
        var visit = WidgetPreviewExampleSelection()
        let untouched = visit
        XCTAssertTrue(visit.select(id: "all_off", for: .lights))
        let chosen = visit.selected(for: .lights)
        XCTAssertTrue(visit.select(id: "triggered", for: .alarm))
        XCTAssertTrue(visit.select(id: "heldNoSnoozes", for: .chargepoint))
        for _ in WidgetPreviewKind.lights.supportedFamilies {
            XCTAssertEqual(visit.selected(for: .lights), chosen)
        }
        XCTAssertFalse(visit.select(chosen, for: .favourites))
        XCTAssertFalse(visit.select(id: "all_off", for: .favourites))
        XCTAssertEqual(visit.selected(for: .lights), chosen)
        XCTAssertEqual(untouched.selected(for: .lights).id, "sample")
        XCTAssertEqual(visit.selected(for: .favourites).id, "sample")
        XCTAssertEqual(chosen.group, "Readings")
        var changed = selectedAllOffSnapshot().summary.off
        changed.removeAll()
        XCTAssertEqual(selectedAllOffSnapshot().summary.offCount, 3)
        XCTAssertEqual(selectedAllOffSnapshot().summary.off.count, 3)
    }

    func testAllOffDoesNotReplaceTheReleasedMixedLightsDefault() {
        let original = LightsSnapshot.sample
        _ = selectedAllOffSnapshot()
        XCTAssertEqual(LightsSnapshot.sample, original)
        XCTAssertEqual(original.summary.headline, "3 on")
        XCTAssertEqual(original.summary.onCount, 3)
        XCTAssertEqual(original.summary.offCount, 1)
        XCTAssertEqual(Set(original.summary.on.map(\.id)), ["light.kitchen", "light.living", "light.desk"])
        XCTAssertEqual(Set(original.summary.on.compactMap(\.percent)), [80, 45, 100])
        XCTAssertEqual(original.summary.pinned.map(\.id), ["light.porch"])
        XCTAssertEqual(original.summary.pinned.map(\.tile), ["Off"])
        XCTAssertEqual(original.summary.off.map(\.id), ["light.hall"])
        XCTAssertEqual(original.checkedAt, "9:41 AM")
    }

    func testUnknownAndUnavailableCannotBecomeSuccessfulAllOff() {
        for state in ["unknown", "unavailable"] {
            let raw = lightsFromTemplate("""
            [{"entity_id":"light.missing","name":"Missing","state":"\(state)","group":false},
             {"entity_id":"light.known","name":"Known","state":"off","group":false}]
            """)
            let summary = lightsSummary(raw, now: Date(timeIntervalSince1970: 0), pinned: ["light.missing"])
            XCTAssertFalse(raw[0].available)
            XCTAssertEqual(summary.headline, "1 unavailable")
            XCTAssertEqual(summary.pinned.map(\.tile), ["Unavailable"])
            XCTAssertEqual(summary.offCount, 1)
        }
    }

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
