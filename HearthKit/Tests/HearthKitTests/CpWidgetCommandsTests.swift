import XCTest
@testable import HearthKit

private actor CpRequestLog {
    var paths: [String] = []
    func add(_ value: String) { paths.append(value) }
}

final class CpWidgetCommandsTests: XCTestCase {
    private var location: CpLocation {
        CpLocation(name: "Amazon Day 1", address: "", deviceIds: [1], bounds: cpBounds(lat: 0, lon: 0))
    }
    private func client(status: String, log: CpRequestLog, supportsStop: Bool = false) -> CpClient {
        CpClient(token: "fixture", userId: 1, transport: { req in
            await log.add(req.url!.path)
            let body = req.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            var response = #"{"result":true}"#
            if body?["user_status"] != nil { response = status }
            if req.url!.path.contains("/sessions/") {
                response = "{\"charging_status\":{\"session_id\":9,\"stop_charge_supported\":\(supportsStop)}}"
            }
            return (Data(response.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    func testIdleAutoJoinsBeforeArming() async throws {
        let log = CpRequestLog()
        let run = try await cpEnableAuto(CpRun(), client: client(status: #"{"user_status":{}}"#, log: log),
                                         location: location, now: 17)
        XCTAssertEqual(run, CpRun(armed: true, startedAt: 17))
        let paths = await log.paths
        XCTAssertTrue(paths.contains { $0.hasSuffix("/waitlist/join") })
    }

    func testQueuedAutoResumesWithoutJoiningOrErasingHistory() async throws {
        let log = CpRequestLog()
        let old = CpRun(snoozeUsed: true, startedAt: 12)
        let run = try await cpEnableAuto(old, client: client(
            status: #"{"user_status":{"waitlist":{"state":{"state":"PASS"}}}}"#, log: log),
            location: location, now: 17)
        XCTAssertEqual(run, CpRun(armed: true, snoozeUsed: true, startedAt: 12))
        let paths = await log.paths
        XCTAssertFalse(paths.contains { $0.hasSuffix("/waitlist/join") })
    }

    func testAutoCannotJoinDuringCharging() async {
        let log = CpRequestLog()
        do {
            _ = try await cpEnableAuto(CpRun(), client: client(
                status: #"{"user_status":{"charging":{"sessionId":9,"state":"charging"}}}"#, log: log),
                location: location, now: 17)
            XCTFail("Charging must not join a waitlist")
        } catch {}
        let paths = await log.paths
        XCTAssertFalse(paths.contains { $0.hasSuffix("/waitlist/join") })
    }

    func testManualCommandsUseTheSameRuntimeAsWidgetButtons() async throws {
        for (command, suffix): (CpCommand, String) in [
            (.accept, "/acceptV2"), (.snooze(3600), "/snoozeV2"), (.unsnooze, "/unsnoozeTheDriver"),
            (.leave, "/waitlist/leave"), (.join, "/waitlist/join")
        ] {
            let log = CpRequestLog()
            try await cpPerformManual(command, client: client(status: #"{"user_status":{}}"#, log: log),
                                      location: location, udid: "fixture")
            let paths = await log.paths
            XCTAssertTrue(paths.contains { $0.hasSuffix(suffix) }, suffix)
        }
    }

    func testUnsupportedStopNeverSendsAStopCommand() async {
        let log = CpRequestLog()
        do {
            try await cpPerformManual(.stop, client: client(
                status: #"{"user_status":{"charging":{"sessionId":9,"state":"charging"}}}"#, log: log),
                location: location, udid: "fixture")
            XCTFail("Stop requires confirmed support")
        } catch {}
        let paths = await log.paths
        XCTAssertTrue(paths.contains { $0.contains("/sessions/") })
        XCTAssertFalse(paths.contains { $0.hasSuffix("/stopSession") })
    }

    func testPauseDuringAutoStatusReadPreventsJoin() async {
        let gate = CommandGate()
        let client = CpClient(token: "fixture", userId: 1, transport: { req in
            let body = req.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if body?["user_status"] != nil {
                await gate.cancel()
                return (Data(#"{"user_status":{}}"#.utf8),
                        HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            await gate.command()
            return (Data(#"{"result":true}"#.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await cpEnableAuto(CpRun(), client: client, location: location, now: 17,
                                       canAct: { await gate.active })
            XCTFail("A paused operation cannot join")
        } catch { XCTAssertTrue(error is CancellationError) }
        let sent = await gate.sent
        XCTAssertEqual(sent, 0)
    }

    func testOperationIdentitySurvivesPersistenceAndFailure() throws {
        let first = CpOperation(command: "accept")
        let second = CpOperation(command: "accept", startedAt: first.startedAt)
        XCTAssertNotEqual(first.id, second.id)
        var failed = first; failed.error = "Retry"
        XCTAssertEqual(try JSONDecoder().decode(CpOperation.self, from: JSONEncoder().encode(failed)).id, first.id)
    }
}

private actor CommandGate {
    var active = true
    var sent = 0
    func cancel() { active = false }
    func command() { sent += 1 }
}
