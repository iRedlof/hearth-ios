import Foundation
import Testing
@testable import HearthKit

/// The Alarm card's garage: a new optional `HaConfig` field, with a one-rule migration from the
/// old Doors selection.
@Suite("Garage door selection")
struct GarageSelectionTests {
    private static let saved = #"{"baseUrl":"https://home.example","token":"t","entityId":"alarm_control_panel.home","#
        + #""lockId":"lock.front","doorIdsJson":"DOORS","doorsChosen":true}"#

    private func decodeSaved(doors: String, garage: String? = nil) throws -> HaConfig {
        var json = Self.saved.replacingOccurrences(of: "DOORS", with: doors.replacingOccurrences(of: "\"", with: "\\\""))
        if let garage { json = String(json.dropLast()) + #","garageId":"\#(garage)"}"# }
        return try JSONDecoder().decode(HaConfig.self, from: Data(json.utf8))
    }

    @Test("A config saved before the garage setting still decodes, with no garage saved")
    func oldConfigDecodes() throws {
        let config = try decodeSaved(doors: #"["lock.front","binary_sensor.back"]"#)
        #expect(config.garageId == nil)
        #expect(config.lockId == "lock.front")
        #expect(config.doorIds == ["lock.front", "binary_sensor.back"])
        #expect(garageSelectedID(config) == nil)
    }

    @Test("The saved garage survives an encode and decode")
    func garageRoundTrips() throws {
        let config = HaConfig(baseUrl: "https://home.example", token: "t", entityId: "", garageId: "cover.garage")
        let decoded = try JSONDecoder().decode(HaConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(garageSelectedID(decoded) == "cover.garage")
    }

    @Test("With no garage saved, the only cover in the old Doors selection becomes the garage")
    func singleCoverMigrates() throws {
        let config = try decodeSaved(doors: #"["lock.front","cover.garage","binary_sensor.back"]"#)
        #expect(config.garageId == nil)
        #expect(garageSelectedID(config) == "cover.garage")
    }

    @Test("A repeated cover id still counts as one cover")
    func repeatedCoverMigrates() throws {
        let config = try decodeSaved(doors: #"["cover.garage","cover.garage"]"#)
        #expect(garageSelectedID(config) == "cover.garage")
    }

    @Test("Two covers, or none, are not guessed between")
    func ambiguousSelectionDoesNotMigrate() throws {
        #expect(garageSelectedID(try decodeSaved(doors: #"["cover.garage","cover.gate"]"#)) == nil)
        #expect(garageSelectedID(try decodeSaved(doors: #"["lock.front"]"#)) == nil)
        #expect(garageSelectedID(try decodeSaved(doors: "[]")) == nil)
    }

    @Test("A saved garage wins over the old Doors selection")
    func savedGarageWins() throws {
        let config = try decodeSaved(doors: #"["cover.gate"]"#, garage: "cover.garage")
        #expect(garageSelectedID(config) == "cover.garage")
    }

    @Test("None, once chosen, is not replaced by the old Doors selection")
    func explicitNoneSticks() throws {
        let config = try decodeSaved(doors: #"["cover.garage"]"#, garage: "")
        #expect(config.garageId == "")
        #expect(garageSelectedID(config) == nil)
    }

    @Test("Only a cover entity can be the garage", arguments: ["lock.front", "binary_sensor.garage", "cover.", "garage"])
    func nonCoverIsNotAGarage(id: String) {
        let config = HaConfig(baseUrl: "https://home.example", token: "t", entityId: "", garageId: id)
        #expect(garageSelectedID(config) == nil)
    }

    @Test("The garage is a door-command target even when it is not in the Doors selection")
    func garageIsACommandTarget() {
        let config = HaConfig(baseUrl: "https://home.example", token: "t", entityId: "",
                              doorIdsJson: #"["binary_sensor.back"]"#, doorsChosen: true, garageId: "cover.garage")
        #expect(doorsSelectedIDs(config) == ["binary_sensor.back", "cover.garage"])
        var none = config; none.garageId = ""
        #expect(doorsSelectedIDs(none) == ["binary_sensor.back"])
    }

    @Test("Changing the garage is a selection change; renaming a lock is not")
    func garageChangeIsASelectionChange() {
        let before = HaConfig(baseUrl: "https://home.example", token: "t", entityId: "", garageId: "cover.garage")
        var other = before; other.garageId = "cover.gate"
        var none = before; none.garageId = ""
        var renamed = before; renamed.lockName = "Entry"
        #expect(haCollectionSelectionChanged(before, other))
        #expect(haCollectionSelectionChanged(before, none))
        #expect(!haCollectionSelectionChanged(before, renamed))
    }

    @Test("The garage picker offers garage and gate covers only, by name")
    func pickerOffersGaragesOnly() {
        let states = #"[{"entity_id":"cover.side","state":"closed","attributes":{"device_class":"gate","friendly_name":"Side Gate"}},"#
            + #"{"entity_id":"cover.blind","state":"open","attributes":{"device_class":"blind","friendly_name":"Blind"}},"#
            + #"{"entity_id":"cover.garage","state":"unavailable","attributes":{"device_class":"garage","friendly_name":"Garage"}},"#
            + #"{"entity_id":"lock.front","state":"locked","attributes":{"friendly_name":"Front Door"}}]"#
        #expect(garageDoorEntities(states) == [HaEntity(id: "cover.garage", name: "Garage"),
                                               HaEntity(id: "cover.side", name: "Side Gate")])
        #expect(garageDoorEntities("not json").isEmpty)
    }
}
