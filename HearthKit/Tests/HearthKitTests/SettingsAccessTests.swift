import XCTest
@testable import HearthKit

final class SettingsAccessTests: XCTestCase {
    func testTokenConnectionWithoutAlarmCanConfigureHomeAssistantWidgets() {
        let config = HaConfig(baseUrl: "https://home.example", token: "fake-token", entityId: "")
        XCTAssertTrue(haSettingsReady(config))
        XCTAssertFalse(config.isComplete)
        XCTAssertFalse(config.hasClimate)
    }

    func testOAuthConnectionWithoutAlarmCanConfigureHomeAssistantWidgets() {
        let config = HaConfig(baseUrl: "https://home.example", token: "", entityId: "",
                              refreshToken: "fake-refresh")
        XCTAssertTrue(haSettingsReady(config))
        XCTAssertFalse(config.isComplete)
    }

    func testAbsentOrUnauthenticatedConnectionHasNoHomeAssistantEntitySettings() {
        XCTAssertFalse(haSettingsReady(nil))
        XCTAssertFalse(haSettingsReady(HaConfig(baseUrl: "https://home.example", token: "", entityId: "")))
        XCTAssertFalse(haSettingsReady(HaConfig(baseUrl: "http://home.example", token: "fake", entityId: "")))
    }
}
