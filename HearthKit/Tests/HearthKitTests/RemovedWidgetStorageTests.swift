import Foundation
import Testing
@testable import HearthKit

/// Values an earlier build saved or was launched with, for widgets that no longer exist.
/// They must read as "no such widget", never crash and never turn into another widget.
@Suite("Removed widgets in stored values")
struct RemovedWidgetStorageTests {
    @Test("A stored Glance kind is not a widget any more")
    func glanceKindIsUnknown() {
        #expect(HomeWidgetKind(rawValue: "glance") == nil)
        #expect(WidgetPreviewKind(rawValue: "glance") == nil)
    }

    @Test("Glance is not offered on Home, in Add a widget or in the catalog")
    func glanceIsNotListed() {
        #expect(!HomeWidgetKind.allCases.map(\.displayName).contains("Glance"))
        #expect(!WidgetPreviewKind.allCases.map(\.title).contains("Glance"))
        let everything = HaConfig(baseUrl: "https://example.com", token: "token",
                                  entityId: "alarm_control_panel.home", climateId: "climate.home",
                                  sensorsJson: "[\"sensor.one\"]", doorIdsJson: "[\"door.one\"]",
                                  scriptIdsJson: "[\"script.one\"]", lightPinsJson: "[\"light.one\"]",
                                  favouriteIdsJson: "[\"fav.one\"]", doorsChosen: true)
        #expect(configuredWidgets(config: everything, chargePointSignedIn: true).count == 9)
    }

    @Test("A stored Doors kind is not a widget any more")
    func doorsKindIsUnknown() {
        #expect(HomeWidgetKind(rawValue: "doors") == nil)
        #expect(WidgetPreviewKind(rawValue: "doors") == nil)
    }

    @Test("Doors is not offered on Home, in Add a widget or in the catalog, even with doors chosen")
    func doorsIsNotListed() {
        #expect(!HomeWidgetKind.allCases.map(\.displayName).contains("Doors"))
        #expect(!WidgetPreviewKind.allCases.map(\.title).contains("Doors"))
        let doorsOnly = HaConfig(baseUrl: "https://example.com", token: "token", entityId: "",
                                 doorIdsJson: "[\"cover.garage\",\"lock.front\"]", doorsChosen: true,
                                 garageId: "cover.garage")
        #expect(configuredWidgets(config: doorsOnly, chargePointSignedIn: false) == [.car])
    }

    @Test("A stored small size is not a widget size any more")
    func smallFamilyIsUnknown() {
        #expect(WidgetPreviewFamily(rawValue: "small") == nil)
        #expect(WidgetPreviewFamily(rawValue: "medium") == .medium)
    }

    @Test("A link from an old small Alarm widget opens no readings screen", arguments: [
        "hearth://alarm-readings/11111111-1111-1111-1111-111111111111",
        "hearth://alarm-readings/unavailable"
    ])
    func oldAlarmReadingsLinkIsIgnored(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(thermostatDestination(from: url) == nil)
        #expect(carReadingsDestination(from: url) == nil)
    }
}
