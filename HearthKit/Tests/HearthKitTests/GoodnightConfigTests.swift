import Testing
import Foundation
@testable import HearthKit

@Suite("GoodnightConfig Model")
struct GoodnightConfigTests {
    @Test("GoodnightConfig.default has expected values")
    func defaultValues() {
        let def = GoodnightConfig.default
        #expect(def.enabled == false)
        #expect(def.startHour == 21)
        #expect(def.endHour == 5)
        #expect(def.armMode == .night)
        #expect(def.keepOnLights.isEmpty)
    }

    @Test("GoodnightArmMode raw values are correct")
    func armModeRawValues() {
        #expect(GoodnightArmMode.night.rawValue == "night")
        #expect(GoodnightArmMode.home.rawValue == "home")
    }

    @Test("GoodnightConfig Codable round-trip with default values")
    func codableDefault() throws {
        let config = GoodnightConfig.default
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GoodnightConfig.self, from: encoded)
        #expect(decoded == config)
    }

    @Test("GoodnightConfig Codable round-trip with enabled config")
    func codableEnabled() throws {
        let config = GoodnightConfig(
            enabled: true,
            startHour: 22,
            endHour: 6,
            armMode: .home,
            keepOnLights: []
        )
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GoodnightConfig.self, from: encoded)
        #expect(decoded == config)
    }

    @Test("GoodnightConfig Codable round-trip with keep-on lights")
    func codableWithKeepOnLights() throws {
        let config = GoodnightConfig(
            enabled: true,
            startHour: 21,
            endHour: 5,
            armMode: .night,
            keepOnLights: ["light.bedroom", "light.hallway"]
        )
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GoodnightConfig.self, from: encoded)
        #expect(decoded == config)
        #expect(decoded.keepOnLights.count == 2)
        #expect(decoded.keepOnLights[0] == "light.bedroom")
        #expect(decoded.keepOnLights[1] == "light.hallway")
    }

    @Test("GoodnightArmMode Codable round-trip")
    func armModeCodable() throws {
        let night = GoodnightArmMode.night
        let encoded = try JSONEncoder().encode(night)
        let decoded = try JSONDecoder().decode(GoodnightArmMode.self, from: encoded)
        #expect(decoded == .night)

        let home = GoodnightArmMode.home
        let encodedHome = try JSONEncoder().encode(home)
        let decodedHome = try JSONDecoder().decode(GoodnightArmMode.self, from: encodedHome)
        #expect(decodedHome == .home)
    }

    @Test("GoodnightConfig equality works")
    func configEquality() {
        let config1 = GoodnightConfig.default
        let config2 = GoodnightConfig()
        #expect(config1 == config2)

        let config3 = GoodnightConfig(enabled: true)
        #expect(config1 != config3)

        let config4 = GoodnightConfig(keepOnLights: ["light.test"])
        #expect(config1 != config4)
    }
}
