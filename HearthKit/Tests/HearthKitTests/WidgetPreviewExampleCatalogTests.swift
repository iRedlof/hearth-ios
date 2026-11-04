import XCTest
@testable import HearthKit

final class WidgetPreviewExampleCatalogTests: XCTestCase {
    func testPendingSnoozeChoicesConsumeWorkingProjection() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for id in ["busy_snooze", "held_pending"] {
            var visit = WidgetPreviewExampleSelection()
            let admitted = visit.select(id: id, for: .chargepoint)
            let selected = visit.selected(for: .chargepoint)
            let example = CpWidgetPreviewExample(rawValue: selected.id)!
            let snapshot = cpWidgetPreviewSnapshot(example, now: now)
            XCTAssertTrue(admitted, "\(id) must be reachable through the normal selector")
            XCTAssertTrue(snapshot.working, "\(id) must consume snooze-pending feedback")
            XCTAssertEqual(snapshot.sub, "Snoozing…")
            XCTAssertEqual(snapshot.keys.last?.label, "Snoozing…")
        }
    }

    func testReleasedChargePointProjectionAndChoiceFingerprintsRemainExact() throws {
        // Released projections remain exact except the deliberately corrected unknown deadline.
        // Normalize only clock formatting; separate deadline/checked-time tests remain authoritative.
        let expected: [String: UInt64] = [
            "heldSnoozeAvailable": 17137810557257717043,
            "heldNoSnoozes": 13620251624840115571,
            "sessionExpiredSignInRequired": 3987974708660834042,
            "available": 4587906824811938432, "signed_out": 4650359989853936590,
            "no_location": 13592687656029219612, "waiting": 1577569889855868770,
            "auto_waiting": 241920383493545376, "pending": 7922386653475646716,
            "offer": 16196332642236928389, "offer_last": 1556769344160279047,
            "held": 7619324071020847156, "held_unknown": 1419528308267677199,
            "dib_held": 7118996603891716517, "offer_no_floor": 10658080650022928117,
            "unknown_deadline": 5869111896774769412, "snoozed": 16605775391549707368,
            "auto_snoozed": 8409005935305985384, "charging": 12239304037065263076,
            "charging_no_stop": 3593845756182000207, "done": 9063043480204704872,
            "fault": 13434545119555273884, "unplugged": 6437700408204563791,
            "overstayed": 5019134098511278303, "blocked": 11466813161671956225
        ]
        XCTAssertEqual(try legacyChargePointFingerprints(now: Date(timeIntervalSince1970: 1_700_000_000)), expected)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for id in expected.keys {
            let snapshot = cpWidgetPreviewSnapshot(CpWidgetPreviewExample(rawValue: id)!, now: now)
            XCTAssertEqual(snapshot.checkedAt, cpClockString(now), id)
            XCTAssertFalse(snapshot.working, id)
            if id == "unknown_deadline" {
                XCTAssertEqual(snapshot.statusDescription, "Deadline unknown. Refresh to check.")
                XCTAssertEqual(snapshot.sub, "Deadline unknown\nRefresh to check")
                XCTAssertEqual(snapshot.keys.map(\.command), ["open", "leave"])
                XCTAssertNil(snapshot.origin)
            } else {
                XCTAssertNil(snapshot.statusDescription, id)
            }
        }
    }

    func testPendingSnoozeSelectionsRetainIndependentPhaseAndInactiveAuthority() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let choices = widgetPreviewExamples(for: .chargepoint)
        let offerIndex = choices.firstIndex(where: { $0.id == "busy_snooze" })!
        XCTAssertEqual(choices[offerIndex + 1].id, "held_pending")
        XCTAssertEqual(choices[offerIndex].group, "Illustrative request feedback")
        XCTAssertEqual(choices[offerIndex + 1].group, "Illustrative request feedback")

        var visit = WidgetPreviewExampleSelection()
        let untouched = visit
        XCTAssertTrue(visit.select(id: "busy_snooze", for: .chargepoint))
        var heldVisit = visit
        XCTAssertTrue(heldVisit.select(id: "held_pending", for: .chargepoint))
        XCTAssertTrue(visit.select(id: "all_off", for: .lights))
        XCTAssertFalse(visit.select(id: "held_pending", for: .lights))
        XCTAssertFalse(visit.select(heldVisit.selected(for: .chargepoint), for: .alarm))
        XCTAssertFalse(visit.select(id: "working_accept", for: .chargepoint))
        for _ in WidgetPreviewKind.chargepoint.supportedFamilies {
            XCTAssertEqual(visit.selected(for: .chargepoint).id, "busy_snooze")
            XCTAssertEqual(heldVisit.selected(for: .chargepoint).id, "held_pending")
        }
        XCTAssertEqual(untouched.selected(for: .chargepoint).id, "heldSnoozeAvailable")
        XCTAssertEqual(heldVisit.selected(for: .lights).id, "sample")
        XCTAssertEqual(visit.selected(for: .lights).id, "all_off")
        XCTAssertEqual(visit.selected(for: .alarm).id, "disarmed")
        let offer = cpWidgetPreviewSnapshot(CpWidgetPreviewExample(rawValue: visit.selected(for: .chargepoint).id)!, now: now)
        let held = cpWidgetPreviewSnapshot(CpWidgetPreviewExample(rawValue: heldVisit.selected(for: .chargepoint).id)!, now: now)
        XCTAssertEqual(offer.keys.first?.command, "accept")
        XCTAssertEqual(held.keys.first?.command, "open")
        XCTAssertEqual(offer.deadline, now.addingTimeInterval(833))
        XCTAssertEqual(held.deadline, now.addingTimeInterval(1690))
        XCTAssertNil(offer.origin)
        XCTAssertNil(held.origin)
    }

    private func legacyChargePointFingerprints(now: Date) throws -> [String: UInt64] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var result: [String: UInt64] = [:]
        for choice in widgetPreviewExamples(for: .chargepoint)
            where !["busy_snooze", "held_pending"].contains(choice.id) {
            let example = CpWidgetPreviewExample(rawValue: choice.id)!
            var snapshot = cpWidgetPreviewSnapshot(example, now: now)
            snapshot.checkedAt = "reference"
            if let deadline = snapshot.deadline {
                snapshot.sub = snapshot.sub.replacingOccurrences(of: cpClockString(deadline), with: "deadline")
            }
            if example == .pending { snapshot.bigAnswer = "waitlist opening" }
            let data = try encoder.encode(snapshot)
            let identity = Data("\(choice.id)|\(choice.title)|\(choice.group)|".utf8)
            result[choice.id] = (identity + data).reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
        }
        return result
    }

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
            XCTAssertEqual(snapshot.working, ["busy_snooze", "held_pending"].contains(choice.id))
        }
    }

}
