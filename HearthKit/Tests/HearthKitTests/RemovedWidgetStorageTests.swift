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
        #expect(configuredWidgets(config: everything, chargePointSignedIn: true).count == 10)
    }
}
