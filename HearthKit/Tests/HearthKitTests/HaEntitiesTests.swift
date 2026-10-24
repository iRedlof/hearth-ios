import XCTest
@testable import HearthKit

final class HaEntitiesTests: XCTestCase {
    // A small slice shaped like a real `GET /api/states` response.
    let statesJson = """
    [
      {"entity_id":"alarm_control_panel.home","state":"disarmed","attributes":{"friendly_name":"Home Alarm"}},
      {"entity_id":"alarm_control_panel.garage","state":"armed_away","attributes":{"friendly_name":"Garage"}},
      {"entity_id":"lock.front_door","state":"locked","attributes":{"friendly_name":"Front Door"}},
      {"entity_id":"climate.living_room","state":"heat","attributes":{"friendly_name":"Living Room"}},
      {"entity_id":"sensor.no_name","state":"1","attributes":{}}
    ]
    """

    func testParsesEntityIdAndFriendlyName() {
        let all = parseEntities(statesJson)
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.first { $0.id == "alarm_control_panel.home" }?.name, "Home Alarm")
    }

    func testFallsBackToEntityIdWhenNoFriendlyName() {
        let all = parseEntities(statesJson)
        XCTAssertEqual(all.first { $0.id == "sensor.no_name" }?.name, "sensor.no_name")
    }

    func testDomainIsThePrefix() {
        XCTAssertEqual(HaEntity(id: "alarm_control_panel.home", name: "x").domain, "alarm_control_panel")
        XCTAssertEqual(HaEntity(id: "lock.front_door", name: "x").domain, "lock")
    }

    func testEntitiesInDomainFiltersAndSortsByName() {
        let panels = entitiesInDomain(parseEntities(statesJson), "alarm_control_panel")
        // "Garage" sorts before "Home Alarm".
        XCTAssertEqual(panels.map(\.id), ["alarm_control_panel.garage", "alarm_control_panel.home"])
    }

    func testGarbageYieldsNoEntities() {
        XCTAssertEqual(parseEntities("<html>502</html>").count, 0)
        XCTAssertEqual(parseEntities(#"{"message":"Entity not found."}"#).count, 0)
    }
}
