import XCTest
@testable import HearthKit

final class ThermostatInlinePickerTests: XCTestCase {
    private let opened = Date(timeIntervalSince1970: 1_800_000_000)
    private let entityID = "climate.room"
    private let scope = "scope"
    private let revision = "revision-1"
    private let selectionRevision = "6F1B6C0E-4C7B-4D1E-9A55-0C1E0B6C7A11"

    private func state(mode: String = "heat", fanMode: String? = "auto",
                       modes: [String] = ["off", "heat", "cool", "heat_cool"],
                       fanModes: [String] = ["auto", "on"]) -> ClimateState {
        ClimateState(mode: mode, action: nil, current: 70, humidity: nil, target: 68, low: nil, high: nil,
                     fanMode: fanMode, fanModes: fanModes, modes: modes, min: 50, max: 90, step: 1, lastChanged: nil)
    }
    private func record(kind: String = "mode", options: [String] = ["off", "heat", "cool", "heat_cool"],
                        current: String? = "heat") -> ThermostatInlinePicker {
        ThermostatInlinePicker(kind: kind, options: options, current: current, entityID: entityID, scope: scope,
            revision: revision, selectionRevision: selectionRevision, expectedMode: "heat", openedAt: opened)
    }
    private func choices(_ record: ThermostatInlinePicker, after age: TimeInterval = 1, entityID: String? = nil,
                         scope: String? = nil, revision: String? = nil,
                         selectionRevision: String? = nil) -> ThermostatInlineChoices? {
        thermostatInlineChoices(record: record, now: opened.addingTimeInterval(age),
            entityID: entityID ?? self.entityID, scope: scope ?? self.scope, revision: revision ?? self.revision,
            selectionRevision: selectionRevision ?? self.selectionRevision)
    }
    private func selection(_ record: ThermostatInlinePicker, kind: String = "mode", option: String,
                           after age: TimeInterval = 1) -> ThermostatInlineSelection? {
        thermostatInlineSelection(record: record, now: opened.addingTimeInterval(age), kind: kind, option: option,
            entityID: entityID, scope: scope, revision: revision, selectionRevision: selectionRevision)
    }

    // MARK: Opening

    func testOpeningModeRecordsTheLiveOptionsAndCurrentMode() throws {
        let opened = try XCTUnwrap(thermostatInlinePicker(state: state(), kind: "mode", entityID: entityID,
            scope: scope, revision: revision, selectionRevision: selectionRevision, expectedMode: "heat", now: opened))
        XCTAssertEqual(opened, record())
    }

    func testOpeningFanRecordsTheFanModes() throws {
        let opened = try XCTUnwrap(thermostatInlinePicker(state: state(), kind: "fan", entityID: entityID,
            scope: scope, revision: revision, selectionRevision: selectionRevision, expectedMode: "heat", now: opened))
        XCTAssertEqual(opened.options, ["auto", "on"])
        XCTAssertEqual(opened.current, "auto")
    }

    func testOpeningDoesNothingWithoutAnOptionOtherThanTheCurrentOne() {
        for (kind, climate) in [("mode", state(modes: ["heat"])), ("fan", state(fanModes: ["auto"])),
                                ("mode", state(modes: [])), ("mode", state(mode: "unavailable")),
                                ("preset", state())] {
            XCTAssertNil(thermostatInlinePicker(state: climate, kind: kind, entityID: entityID, scope: scope,
                revision: revision, selectionRevision: selectionRevision, expectedMode: "heat", now: opened),
                "\(kind) \(climate.modes) \(climate.fanModes)")
        }
    }

    func testOpeningNeedsACompleteCardBinding() {
        for (entity, scope, revision, selection) in [("", scope, revision, selectionRevision),
                                                     (entityID, "", revision, selectionRevision),
                                                     (entityID, scope, "", selectionRevision),
                                                     (entityID, scope, revision, "")] {
            XCTAssertNil(thermostatInlinePicker(state: state(), kind: "mode", entityID: entity, scope: scope,
                revision: revision, selectionRevision: selection, expectedMode: "heat", now: opened))
        }
    }

    // MARK: Showing

    func testMatchingRecordShowsItsChoicesWithTheCurrentOneMarked() throws {
        let shown = try XCTUnwrap(choices(record()))
        XCTAssertEqual(shown.kind, "mode")
        XCTAssertEqual(shown.options.map(\.value), ["off", "heat", "cool", "heat_cool"])
        XCTAssertEqual(shown.options.map(\.label), ["Off", "Heat", "Cool", "Auto"])
        XCTAssertEqual(shown.options.map(\.isCurrent), [false, true, false, false])
        XCTAssertEqual(shown.expiresAt, opened.addingTimeInterval(thermostatInlinePickerLifetime))
    }

    func testExpiredRecordShowsNothing() {
        XCTAssertNil(choices(record(), after: 21))
        XCTAssertNil(choices(record(), after: 3600))
    }

    func testLifetimeBoundaryIsTwentySecondsExclusive() {
        XCTAssertEqual(thermostatInlinePickerLifetime, 20)
        XCTAssertNotNil(choices(record(), after: 0))
        XCTAssertNotNil(choices(record(), after: 19.999))
        XCTAssertNil(choices(record(), after: 20))
        XCTAssertNil(choices(record(), after: -0.001), "a record from the future is not shown")
        XCTAssertNil(choices(record(), after: .nan))
    }

    func testWrongEntityShowsNothing() { XCTAssertNil(choices(record(), entityID: "climate.other")) }
    func testWrongScopeShowsNothing() { XCTAssertNil(choices(record(), scope: "other-scope")) }
    func testWrongRevisionShowsNothing() { XCTAssertNil(choices(record(), revision: "revision-2")) }
    func testWrongSelectionRevisionShowsNothing() {
        XCTAssertNil(choices(record(), selectionRevision: "0E0F5A0B-6F5B-4B27-8B7B-5C6B7F2B9D10"))
        XCTAssertNil(choices(record(), selectionRevision: ""))
    }

    func testEmptyOptionsShowNothing() {
        XCTAssertNil(choices(record(options: [])))
        XCTAssertNil(choices(record(options: ["heat"])), "only the current option is not a choice")
        XCTAssertNil(choices(record(kind: "preset")))
    }

    func testRepeatedOptionsAreShownOnce() throws {
        let shown = try XCTUnwrap(choices(record(options: ["off", "heat", "off", "cool"])))
        XCTAssertEqual(shown.options.map(\.value), ["off", "heat", "cool"])
    }

    func testOptionNamesReuseTheCardsModeAndFanNames() {
        XCTAssertEqual(["off", "heat", "cool", "heat_cool", "auto", "fan_only", "dry"].map {
            thermostatInlineOptionLabel(kind: "mode", option: $0)
        }, ["Off", "Heat", "Cool", "Auto", "Auto", "Fan", "Dry"])
        XCTAssertEqual(["auto", "on", "low"].map { thermostatInlineOptionLabel(kind: "fan", option: $0) },
                       ["Auto", "On", "Low"])
    }

    func testAccessibilityNamesTheActionOfEachChip() throws {
        let mode = try XCTUnwrap(choices(record()))
        XCTAssertEqual(mode.options.map { thermostatInlineAccessibilityLabel(kind: mode.kind, option: $0) },
            ["Set mode to Off", "Mode Heat, current. Close", "Set mode to Cool", "Set mode to Auto"])
        let fan = try XCTUnwrap(choices(record(kind: "fan", options: ["auto", "on"], current: "auto")))
        XCTAssertEqual(fan.options.map { thermostatInlineAccessibilityLabel(kind: fan.kind, option: $0) },
            ["Fan Auto, current. Close", "Set fan to On"])
    }

    // MARK: Choosing

    func testChoosingTheCurrentOptionOnlyClosesTheRow() {
        XCTAssertEqual(selection(record(), option: "heat"), .close)
    }

    func testChoosingAnotherOptionAppliesIt() {
        XCTAssertEqual(selection(record(), option: "cool"), .apply("cool"))
        XCTAssertEqual(selection(record(kind: "fan", options: ["auto", "on"], current: "auto"), kind: "fan", option: "on"),
                       .apply("on"))
    }

    func testChoosingIsRefusedForAnOptionKindOrCardTheRecordDidNotOffer() {
        XCTAssertNil(selection(record(), option: "dry"))
        XCTAssertNil(selection(record(), kind: "fan", option: "heat"))
        XCTAssertNil(selection(record(), option: "cool", after: 20))
        XCTAssertNil(thermostatInlineSelection(record: record(), now: opened, kind: "mode", option: "cool",
            entityID: entityID, scope: scope, revision: "revision-2", selectionRevision: selectionRevision))
    }

    // MARK: Card and account ownership

    private func context(mode: String = "heat") throws -> HaStoreSnapshot {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = HaStateStore(directory: directory,
            initialConfig: HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "",
                climateId: entityID, sensorsJson: "[]"), initialScope: scope)
        let json = #"{"entity_id":"climate.room","state":"\#(mode)","attributes":{"current_temperature":67,"temperature":68,"# +
            #""hvac_modes":["off","heat","cool"],"fan_mode":"auto","fan_modes":["auto","on"]}}"#
        return try XCTUnwrap(store.merge([entityID: HaStateReading(entityID: entityID, json: json, checkedAt: opened)],
            expectedScope: try store.snapshot().scope))
    }
    private func record(for context: HaStoreSnapshot, kind: String = "mode") throws -> ThermostatInlinePicker {
        ThermostatInlinePicker(kind: kind, options: kind == "fan" ? ["auto", "on"] : ["off", "heat", "cool"],
            current: kind == "fan" ? "auto" : "heat", entityID: entityID, scope: context.scope,
            revision: context.climateRevision,
            selectionRevision: try XCTUnwrap(context.thermostatSelectionRevision), expectedMode: "heat", openedAt: opened)
    }

    func testChoicesAreDrawnOnlyOnTheCardThatOpenedThem() throws {
        let context = try context()
        let card = thermostatEnvelope(context, now: opened).snapshot
        let shown = try XCTUnwrap(thermostatInlineChoices(record: try record(for: context),
            now: opened.addingTimeInterval(2), snapshot: card))
        XCTAssertEqual(shown.options.map(\.label), ["Off", "Heat", "Cool"])
        XCTAssertNil(thermostatInlineChoices(record: nil, now: opened, snapshot: card))
        XCTAssertNil(thermostatInlineChoices(record: try record(for: context), now: opened, snapshot: .sample))
    }

    func testChoicesAreHiddenWhileTheCardCannotPickThatControl() throws {
        let context = try context()
        var card = thermostatEnvelope(context, now: opened).snapshot
        card.canPickMode = false
        XCTAssertNil(thermostatInlineChoices(record: try record(for: context), now: opened, snapshot: card))
        XCTAssertNotNil(thermostatInlineChoices(record: try record(for: context, kind: "fan"), now: opened, snapshot: card))
        card.canPickFan = false
        XCTAssertNil(thermostatInlineChoices(record: try record(for: context, kind: "fan"), now: opened, snapshot: card))
    }

    func testRecordIsOwnedOnlyByTheSelectionThatOpenedIt() throws {
        let context = try context()
        let owned = try record(for: context)
        XCTAssertTrue(thermostatInlinePickerOwned(owned, by: context))
        XCTAssertFalse(thermostatInlinePickerOwned(owned, by: nil))
        XCTAssertFalse(thermostatInlinePickerOwned(record(), by: context), "another account scope or selection")
        let otherEntity = ThermostatInlinePicker(kind: owned.kind, options: owned.options, current: owned.current,
            entityID: "climate.other", scope: owned.scope, revision: owned.revision,
            selectionRevision: owned.selectionRevision, expectedMode: owned.expectedMode, openedAt: owned.openedAt)
        XCTAssertFalse(thermostatInlinePickerOwned(otherEntity, by: context))
    }

    func testRecordSurvivesStorageUnchanged() throws {
        let data = try JSONEncoder().encode(record())
        XCTAssertEqual(try JSONDecoder().decode(ThermostatInlinePicker.self, from: data), record())
    }
}
