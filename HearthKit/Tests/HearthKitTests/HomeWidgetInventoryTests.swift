import Testing
@testable import HearthKit

@Suite("HomeWidgetInventory Tests")
struct HomeWidgetInventoryTests {

    @Test("Empty config returns no widgets")
    func emptyConfigReturnsNoWidgets() {
        let config = HaConfig(baseUrl: "", token: "", entityId: "")
        let widgets = configuredWidgets(config: config, chargePointSignedIn: false)
        #expect(widgets.isEmpty)
    }

    @Test("Fully configured returns all widgets")
    func fullyConfiguredReturnsAllWidgets() {
        let config = HaConfig(
            baseUrl: "https://example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            climateId: "climate.home",
            sensorsJson: "[\"sensor.one\"]",
            doorIdsJson: "[\"door.one\"]",
            scriptIdsJson: "[\"script.one\"]",
            lightPinsJson: "[\"light.one\"]",
            favouriteIdsJson: "[\"fav.one\"]",
            doorsChosen: true
        )
        let widgets = configuredWidgets(config: config, chargePointSignedIn: true)

        // Should return all 11 widgets in allCases order (including glance)
        #expect(widgets.count == 11)
        #expect(widgets == HomeWidgetKind.allCases)
    }

    @Test("Partial config returns subset")
    func partialConfigReturnsSubset() {
        let config = HaConfig(
            baseUrl: "https://example.com",
            token: "token",
            entityId: "",
            climateId: "climate.home",
            lightPinsJson: "[\"light.one\", \"light.two\"]"
        )
        let widgets = configuredWidgets(config: config, chargePointSignedIn: true)

        // Should have: car, thermostat, lights, chargePoint
        #expect(widgets.contains(.car))
        #expect(widgets.contains(.thermostat))
        #expect(widgets.contains(.lights))
        #expect(widgets.contains(.chargePoint))
        #expect(widgets.count == 4)

        // Should NOT have alarm (no entityId configured)
        #expect(!widgets.contains(.alarm))
    }

    @Test("ChargePoint requires sign-in flag")
    func chargePointRequiresSignIn() {
        let config = HaConfig(baseUrl: "https://example.com", token: "token", entityId: "")

        let withoutSignIn = configuredWidgets(config: config, chargePointSignedIn: false)
        #expect(!withoutSignIn.contains(.chargePoint))

        let withSignIn = configuredWidgets(config: config, chargePointSignedIn: true)
        #expect(withSignIn.contains(.chargePoint))
    }

    @Test("Activity and battery both use sensorIds")
    func activityAndBatteryUseSensors() {
        let config = HaConfig(
            baseUrl: "https://example.com",
            token: "token",
            entityId: "",
            sensorsJson: "[\"sensor.test\"]"
        )
        let widgets = configuredWidgets(config: config, chargePointSignedIn: false)

        #expect(widgets.contains(.activity))
        #expect(widgets.contains(.battery))
    }

    @Test("All widget kinds have display properties")
    func allKindsHaveDisplayProperties() {
        for kind in HomeWidgetKind.allCases {
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.icon.isEmpty)
            // Just verify hue returns a valid case
            _ = kind.hue
        }
    }
}
