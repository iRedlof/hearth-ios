import Testing
import Foundation
@testable import HearthKit

@Suite("Add Widget Chip")
struct AddWidgetChipTests {

    // MARK: - Chip State Tests

    @Test("Returns added when alarm is configured")
    func addedWhenAlarmConfigured() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh"
        )
        let chip = addWidgetChip(kind: .alarm, config: config, cpSignedIn: false)
        #expect(chip == .added)
    }

    @Test("Returns needsHA for alarm without connection")
    func needsHaForAlarm() {
        let config = HaConfig(
            baseUrl: "",
            token: "",
            entityId: "",
            refreshToken: ""
        )
        let chip = addWidgetChip(kind: .alarm, config: config, cpSignedIn: false)
        #expect(chip == .needsHA)
    }

    @Test("Returns needsHA for glance without connection")
    func needsHaForGlance() {
        let config = HaConfig(
            baseUrl: "",
            token: "",
            entityId: "",
            refreshToken: ""
        )
        let chip = addWidgetChip(kind: .glance, config: config, cpSignedIn: false)
        #expect(chip == .needsHA)
    }

    @Test("Returns added for glance when HA is complete")
    func addedForGlanceWhenComplete() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh"
        )
        let chip = addWidgetChip(kind: .glance, config: config, cpSignedIn: false)
        #expect(chip == .added)
    }

    @Test("Returns needsCP for ChargePoint without sign-in")
    func needsCpForChargePoint() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh"
        )
        let chip = addWidgetChip(kind: .chargePoint, config: config, cpSignedIn: false)
        #expect(chip == .needsCP)
    }

    @Test("Returns added for ChargePoint when signed in")
    func addedForChargePointWhenSignedIn() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh"
        )
        let chip = addWidgetChip(kind: .chargePoint, config: config, cpSignedIn: true)
        #expect(chip == .added)
    }

    @Test("Returns added for car when HA has auth")
    func addedForCarWhenHaReady() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "",
            refreshToken: "refresh"
        )
        let chip = addWidgetChip(kind: .car, config: config, cpSignedIn: false)
        #expect(chip == .added)
    }

    @Test("Returns needsHA for car without auth")
    func needsHaForCarWithoutAuth() {
        let config = HaConfig(
            baseUrl: "",
            token: "",
            entityId: "",
            refreshToken: ""
        )
        let chip = addWidgetChip(kind: .car, config: config, cpSignedIn: false)
        #expect(chip == .needsHA)
    }

    @Test("Returns needsHA for thermostat without climate")
    func needsHaForThermostatWithoutClimate() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh",
            climateId: ""
        )
        let chip = addWidgetChip(kind: .thermostat, config: config, cpSignedIn: false)
        #expect(chip == .needsHA)
    }

    @Test("Returns added for thermostat with climate")
    func addedForThermostatWithClimate() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh",
            climateId: "climate.living_room"
        )
        let chip = addWidgetChip(kind: .thermostat, config: config, cpSignedIn: false)
        #expect(chip == .added)
    }

    @Test("Returns added for quick actions when configured")
    func addedForQuickActionsWhenConfigured() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh",
            scriptIdsJson: "[\"script.one\"]"
        )
        let chip = addWidgetChip(kind: .quick, config: config, cpSignedIn: false)
        #expect(chip == .added)
    }

    @Test("Returns needsHA for quick actions without scripts")
    func needsHaForQuickActionsWithoutScripts() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh",
            scriptIdsJson: "[]"
        )
        let chip = addWidgetChip(kind: .quick, config: config, cpSignedIn: false)
        #expect(chip == .needsHA)
    }

    @Test("Returns added for lights when pins configured")
    func addedForLightsWhenPinsConfigured() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh",
            lightPinsJson: "[\"light.one\"]"
        )
        let chip = addWidgetChip(kind: .lights, config: config, cpSignedIn: false)
        #expect(chip == .added)
    }

    @Test("Returns needsHA for lights without pins")
    func needsHaForLightsWithoutPins() {
        let config = HaConfig(
            baseUrl: "https://ha.example.com",
            token: "token",
            entityId: "alarm_control_panel.home",
            refreshToken: "refresh",
            lightPinsJson: "[]"
        )
        let chip = addWidgetChip(kind: .lights, config: config, cpSignedIn: false)
        #expect(chip == .needsHA)
    }

    // MARK: - Category Tests

    @Test("Control category includes alarm, thermostat, lights, favourites, quick")
    func controlCategory() {
        #expect(addWidgetCategory(.alarm) == .control)
        #expect(addWidgetCategory(.thermostat) == .control)
        #expect(addWidgetCategory(.lights) == .control)
        #expect(addWidgetCategory(.favourites) == .control)
        #expect(addWidgetCategory(.quick) == .control)
    }

    @Test("Check category includes doors, glance, activity, battery")
    func checkCategory() {
        #expect(addWidgetCategory(.doors) == .check)
        #expect(addWidgetCategory(.glance) == .check)
        #expect(addWidgetCategory(.activity) == .check)
        #expect(addWidgetCategory(.battery) == .check)
    }

    @Test("Car charging category includes car and ChargePoint")
    func carChargingCategory() {
        #expect(addWidgetCategory(.car) == .carCharging)
        #expect(addWidgetCategory(.chargePoint) == .carCharging)
    }
}
