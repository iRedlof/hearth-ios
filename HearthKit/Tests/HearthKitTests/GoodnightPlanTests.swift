import Testing
import Foundation
@testable import HearthKit

@Suite("GoodnightPlan")
struct GoodnightPlanTests {
    @Test("covers: filters doorIds to cover.* only")
    func coversFromDoorIds() {
        let config = GoodnightConfig()
        let haConfig = HaConfig(
            baseUrl: "https://ha.local",
            token: "token",
            entityId: "alarm_control_panel.home",
            doorIdsJson: #"["cover.garage","lock.front","door.side"]"#
        )
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: [], panelSupportsNight: false)
        #expect(plan.covers == ["cover.garage"])
    }

    @Test("covers: empty when no covers in doorIds")
    func coversEmptyWhenNoDoors() {
        let config = GoodnightConfig()
        let haConfig = HaConfig(
            baseUrl: "https://ha.local",
            token: "token",
            entityId: "alarm_control_panel.home",
            doorIdsJson: #"["lock.front"]"#
        )
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: [], panelSupportsNight: false)
        #expect(plan.covers == [])
    }

    @Test("lightsOff: all lights minus keep-on")
    func lightsOffExcludesKeepOn() {
        let config = GoodnightConfig(keepOnLights: ["light.bedroom","light.hall"])
        let haConfig = HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "alarm_control_panel.home")
        let allLights = ["light.living_room","light.bedroom","light.kitchen","light.hall"]
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: allLights, panelSupportsNight: false)
        #expect(plan.lightsOff == ["light.living_room","light.kitchen"])
    }

    @Test("lockId: included when valid lock.* entity")
    func lockIdIncluded() {
        let config = GoodnightConfig()
        let haConfig = HaConfig(
            baseUrl: "https://ha.local",
            token: "token",
            entityId: "alarm_control_panel.home",
            lockId: "lock.front_door"
        )
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: [], panelSupportsNight: false)
        #expect(plan.lockId == "lock.front_door")
    }

    @Test("lockId: nil when empty or invalid")
    func lockIdNilWhenInvalid() {
        let config = GoodnightConfig()
        let haConfig1 = HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "alarm_control_panel.home", lockId: "")
        let haConfig2 = HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "alarm_control_panel.home", lockId: "invalid")
        let plan1 = planGoodnight(config: config, haConfig: haConfig1, allLights: [], panelSupportsNight: false)
        let plan2 = planGoodnight(config: config, haConfig: haConfig2, allLights: [], panelSupportsNight: false)
        #expect(plan1.lockId == nil)
        #expect(plan2.lockId == nil)
    }

    @Test("armMode: .night when panel supports night")
    func armModeNightWhenSupported() {
        let config = GoodnightConfig(armMode: .night)
        let haConfig = HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "alarm_control_panel.home")
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: [], panelSupportsNight: true)
        #expect(plan.armMode == .night)
    }

    @Test("armMode: .home fallback when night unsupported")
    func armModeHomeFallbackWhenNightUnsupported() {
        let config = GoodnightConfig(armMode: .night)
        let haConfig = HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "alarm_control_panel.home")
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: [], panelSupportsNight: false)
        #expect(plan.armMode == .home)
    }

    @Test("armMode: .home when preferred")
    func armModeHomeWhenPreferred() {
        let config = GoodnightConfig(armMode: .home)
        let haConfig = HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "alarm_control_panel.home")
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: [], panelSupportsNight: false)
        #expect(plan.armMode == .home)
    }

    @Test("armMode: nil when no alarm configured")
    func armModeNilWhenNoAlarm() {
        let config = GoodnightConfig()
        let haConfig = HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "")
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: [], panelSupportsNight: false)
        #expect(plan.armMode == nil)
    }

    @Test("full plan: all steps populated")
    func fullPlan() {
        let config = GoodnightConfig(armMode: .night, keepOnLights: ["light.hall"])
        let haConfig = HaConfig(
            baseUrl: "https://ha.local",
            token: "token",
            entityId: "alarm_control_panel.home",
            lockId: "lock.front",
            doorIdsJson: #"["cover.garage","lock.back"]"#
        )
        let allLights = ["light.living_room","light.hall","light.kitchen"]
        let plan = planGoodnight(config: config, haConfig: haConfig, allLights: allLights, panelSupportsNight: true)
        #expect(plan.covers == ["cover.garage"])
        #expect(plan.lightsOff == ["light.living_room","light.kitchen"])
        #expect(plan.lockId == "lock.front")
        #expect(plan.armMode == .night)
    }
}
