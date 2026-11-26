import XCTest
@testable import HearthKit

final class TileFetchTests: XCTestCase {
    private let unconfigured = HaConfig(baseUrl: "", token: "", entityId: "")
    private let connection = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "")

    func testMissingConnectionDoesNotInventInteractiveEntities() async {
        let favourites = await fetchFavouritesSnapshot(unconfigured)
        let lights = await fetchLightsSnapshot(unconfigured)
        let quick = await fetchQuickSnapshot(unconfigured)
        XCTAssertTrue(favourites.items.isEmpty)
        XCTAssertTrue(lights.summary.on.isEmpty)
        XCTAssertTrue(lights.summary.pinned.isEmpty)
        XCTAssertTrue(quick.keys.isEmpty)
    }

    func testEmptySelectionDoesNotInventControls() async {
        let favourites = await fetchFavouritesSnapshot(connection)
        let quick = await fetchQuickSnapshot(connection)
        XCTAssertTrue(favourites.items.isEmpty)
        XCTAssertTrue(quick.keys.isEmpty)
        XCTAssertEqual(favourites.state, .choose)
        XCTAssertEqual(quick.state, .choose)
    }

    func testSuccessfulEmptyAndMalformedLightsHaveDifferentStates() async {
        let empty = await fetchLightsSnapshot(connection, read: { "[]" })
        XCTAssertEqual(empty.state, .empty)
        XCTAssertFalse(empty.checkedAt.isEmpty)
        let failed = await fetchLightsSnapshot(connection, read: { "{\"error\":\"bad template\"}" })
        XCTAssertEqual(failed.state, .failed)
        XCTAssertTrue(failed.checkedAt.isEmpty)
        XCTAssertNotNil(failed.error)
        let unsupported = await fetchLightsSnapshot(connection, read: { "[{\"entity_id\":\"light.x\",\"state\":\"bogus\"}]" })
        XCTAssertEqual(unsupported.state, .failed)
        XCTAssertTrue(unsupported.checkedAt.isEmpty)
    }

    func testPartialFavouriteFailurePreservesOrderAndUnavailableTile() async {
        var config = connection
        config.favouriteIdsJson = "[\"switch.first\",\"light.second\"]"
        let result = await fetchFavouritesSnapshot(config, read: { id in
            if id == "light.second" { throw HaError("Signed out: sign in again") }
            return "{\"entity_id\":\"switch.first\",\"state\":\"on\",\"attributes\":{\"friendly_name\":\"First\"}}"
        })
        XCTAssertEqual(result.items.map(\.id), ["switch.first", "light.second"])
        XCTAssertEqual(result.items.map(\.available), [true, false])
        XCTAssertEqual(result.state, .ready)
        XCTAssertNotNil(result.error)
        XCTAssertFalse(result.items[0].requestedOn)
    }

    func testUnknownAndMismatchedFavouriteNeverBecomeActionableOff() throws {
        let unknown = try favouriteFromState("{\"entity_id\":\"switch.first\",\"state\":\"unknown\"}", id: "switch.first")
        XCTAssertFalse(unknown.available)
        XCTAssertThrowsError(try favouriteFromState("{\"entity_id\":\"switch.other\",\"state\":\"off\"}", id: "switch.first"))
    }

    func testQuickFailureDoesNotCreateRunnableFallbackName() async {
        var config = connection
        config.scriptIdsJson = "[\"script.movie\"]"
        let result = await fetchQuickSnapshot(config, read: { _ in throw URLError(.timedOut) })
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.keys.map(\.available), [false])
        XCTAssertTrue(result.checkedAt.isEmpty)
    }

    func testOutOfRangeColorAndBrightnessCannotTrapOrInventPercent() {
        let rows = lightsFromTemplate("""
        [{"entity_id":"light.first","state":"on","name":"First","brightness":1e99,"rgb":[-1,300,0]}]
        """)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].rgb)
        XCTAssertNil(rows[0].percent)
    }

    func testUnavailableLightCannotBecomeAllOff() {
        let lights = lightsFromTemplate("[{\"entity_id\":\"light.first\",\"state\":\"unavailable\",\"name\":\"First\"}]")
        let summary = lightsSummary(lights, now: .now)
        XCTAssertEqual(summary.headline, "1 unavailable")
        XCTAssertEqual(summary.offCount, 0)
        XCTAssertFalse(summary.on[0].available)
    }
}
