import Testing
import Foundation
@testable import HearthKit

@Suite("GoodnightStore Load Path")
struct GoodnightStoreTests {

    @Test("Load returns default when key is absent")
    func loadAbsentKeyReturnsDefault() {
        let suite = "test.goodnight.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        // Key does not exist
        #expect(defaults.data(forKey: "goodnight.config") == nil)

        // Call production load() with test defaults
        let result = GoodnightStore.load(defaults: defaults)
        #expect(result == GoodnightConfig.default)
        #expect(result.enabled == false)
        #expect(result.startHour == 21)
        #expect(result.endHour == 5)
    }

    @Test("Load returns default when JSON is corrupt")
    func loadCorruptJsonReturnsDefault() {
        let suite = "test.goodnight.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        // Store genuinely corrupt JSON
        let corruptData = Data("{ not valid json }".utf8)
        defaults.set(corruptData, forKey: "goodnight.config")

        // Call production load() with test defaults
        let result = GoodnightStore.load(defaults: defaults)
        #expect(result == GoodnightConfig.default)
    }

    @Test("Load returns default when JSON has wrong structure")
    func loadWrongStructureReturnsDefault() {
        let suite = "test.goodnight.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        // Store JSON with wrong structure (missing required fields)
        let wrongData = Data(#"{"foo":"bar"}"#.utf8)
        defaults.set(wrongData, forKey: "goodnight.config")

        // Call production load() with test defaults
        let result = GoodnightStore.load(defaults: defaults)
        #expect(result == GoodnightConfig.default)
    }

    @Test("Valid round-trip through production save/load")
    func validRoundTrip() {
        let suite = "test.goodnight.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        // Create a config
        let original = GoodnightConfig(
            enabled: true,
            startHour: 22,
            endHour: 6,
            armMode: .home,
            keepOnLights: ["light.bedroom", "light.hallway"]
        )

        // Call production save()
        GoodnightStore.save(original, defaults: defaults)

        // Call production load()
        let loaded = GoodnightStore.load(defaults: defaults)

        #expect(loaded == original)
        #expect(loaded.enabled == true)
        #expect(loaded.startHour == 22)
        #expect(loaded.endHour == 6)
        #expect(loaded.armMode == .home)
        #expect(loaded.keepOnLights == ["light.bedroom", "light.hallway"])
    }
}
