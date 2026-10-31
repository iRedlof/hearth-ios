import XCTest
@testable import HearthKit

final class CpActionOriginEnvelopeTests: XCTestCase {
    func testFixtureOriginCannotDecodeInProductionOrWithoutItsFixtureDependency() throws {
        let store = CpStateStore(directory: try CpStoreFixture.directory(self))
        let origin = try XCTUnwrap(store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now).renderedOrigin)
        let fixture = try XCTUnwrap(CpActionOriginEnvelope.encode(origin, inFixture: true))
        XCTAssertNil(CpActionOriginEnvelope.decode(fixture, inFixture: false))
        XCTAssertEqual(CpActionOriginEnvelope.decode(fixture, inFixture: true), origin)
        let live = try XCTUnwrap(CpActionOriginEnvelope.encode(origin, inFixture: false))
        XCTAssertEqual(CpActionOriginEnvelope.decode(live, inFixture: false), origin)
        XCTAssertNil(CpActionOriginEnvelope.decode(live, inFixture: true))
    }

    func testMalformedOrOverlongFixtureEnvelopeCannotEnterAStoreBoundary() {
        XCTAssertNil(CpActionOriginEnvelope.decode("cp-fixture-v1:{}", inFixture: true))
        XCTAssertNil(CpActionOriginEnvelope.decode("cp-fixture-v1:" + String(repeating: "x", count: 4097), inFixture: true))
        XCTAssertNil(CpActionOriginEnvelope.decode("cp-fixture-v1:cp-fixture-v1:{}", inFixture: true))
    }
}
