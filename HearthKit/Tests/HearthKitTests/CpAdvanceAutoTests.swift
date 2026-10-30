import XCTest
@testable import HearthKit

/// The auto-waitlist runtime (`cpAdvanceAuto`) acts on the pure engine's decision and surfaces the
/// notification that Android posts for that transition. Driven with a stub transport — no network.
final class CpAdvanceAutoTests: XCTestCase {
    private func resp(_ url: URL, _ body: String) -> (Data, HTTPURLResponse) {
        (body.data(using: .utf8)!, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    /// A client whose accept/snooze succeed (or fail) and whose snooze-detail reports a snooze left.
    private func client(ok: Bool = true) -> CpClient {
        CpClient(token: "t", userId: 1, transport: { req in
            let u = req.url!.absoluteString
            if u.contains("get_notification_detail") {
                return (#"{"response":{"remainingSnoozeCount":1}}"#.data(using: .utf8)!,
                        HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (("{\"result\":\(ok)}").data(using: .utf8)!,
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    /// userStatus body for a waitlist state. untilMs = (start+dur)*1000; a token makes it answerable.
    private func statusJSON(_ state: String, start: Int64 = 0, dur: Int64 = 0,
                            token: String = "", charging: Bool = false) -> String {
        var s = "\"state\":\"\(state)\""
        if start > 0 { s += ",\"startTimeUTC\":\(start),\"duration\":\(dur),\"deviceId\":1" }
        if !token.isEmpty { s += ",\"token\":\"\(token)\"" }
        let charge = charging ? ",\"charging\":{\"sessionId\":99,\"state\":\"charging\"}" : ""
        return "{\"user_status\":{\"waitlist\":{\"state\":{\(s)}}\(charge)}}"
    }

    private let armed = CpRun(armed: true)

    func testAcceptEmitsAccepted() async {
        // ACCEPT_PENDING inside the 2-min margin → accept now → "Accepted".
        let r = await cpAdvanceAuto(armed, client: client(),
                                    statusJson: statusJSON("ACCEPT_PENDING", start: 10, dur: 50), now: 0)
        XCTAssertEqual(r.alert, .accepted)
    }

    func testAcceptFailureEmitsFailed() async {
        let r = await cpAdvanceAuto(armed, client: client(ok: false),
                                    statusJson: statusJSON("ACCEPT_PENDING", start: 10, dur: 50), now: 0)
        XCTAssertEqual(r.alert, .failed)
    }

    func testOfferEmittedOnceThenDeduped() async {
        // Deadline far away → engine schedules a pre-deadline wake and posts the offer once.
        let json = statusJSON("ACCEPT_PENDING", start: 100, dur: 500)   // untilMs 600_000 > margin
        let first = await cpAdvanceAuto(armed, client: client(), statusJson: json, now: 0)
        XCTAssertEqual(first.alert, .offer)
        XCTAssertTrue(first.run.offerPushed)
        let second = await cpAdvanceAuto(first.run, client: client(), statusJson: json, now: 0)
        XCTAssertNil(second.alert)   // same offer, already notified
    }

    func testSecondOfferWhenSnoozeSpent() async {
        let run = CpRun(armed: true, snoozeUsed: true)
        let r = await cpAdvanceAuto(run, client: client(),
                                    statusJson: statusJSON("ACCEPT_PENDING", start: 100, dur: 500), now: 0)
        XCTAssertEqual(r.alert, .secondOffer)
    }

    func testSnoozeEmitsSnoozed() async {
        // Held with a snooze available → auto-snooze → "Snoozed".
        let json = statusJSON("PENDING_PLUG_IN", start: 10, dur: 50, token: "T0K3N")
        let r = await cpAdvanceAuto(armed, client: client(), statusJson: json, now: 0)
        XCTAssertEqual(r.alert, .snoozed)
    }

    func testChargingEmitsDone() async {
        let r = await cpAdvanceAuto(armed, client: client(),
                                    statusJson: statusJSON("CHARGING", charging: true), now: 0)
        XCTAssertEqual(r.alert, .done)
        XCTAssertFalse(r.run.armed)
    }

    func testNotArmedEmitsNothing() async {
        let r = await cpAdvanceAuto(CpRun(armed: false), client: client(),
                                    statusJson: statusJSON("ACCEPT_PENDING", start: 10, dur: 50), now: 0)
        XCTAssertNil(r.alert)
    }

    func testMissingTimingNeverAcceptsOrSnoozes() async {
        for state in ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"] {
            let json = """
            {"user_status":{"waitlist":{"state":{"state":"\(state)","deviceId":1,"token":"test"},"stations":[]}}}
            """
            let result = await cpAdvanceAuto(armed, client: client(), statusJson: json, now: 1_700_000_000_000)
            XCTAssertNil(result.alert, state)
            XCTAssertEqual(result.run, armed, state)
        }
    }

    func testCancelledAutoCannotDispatchAccept() async {
        let result = await cpAdvanceAuto(armed, client: client(),
            statusJson: statusJSON("ACCEPT_PENDING", start: 10, dur: 50), now: 0,
            canAct: { false })
        XCTAssertNil(result.alert)
        XCTAssertEqual(result.run, armed)
    }

    func testCancelledDuringAllowanceReadCannotDispatchSnooze() async {
        let gate = AutoGate()
        let client = CpClient(token: "fixture", userId: 1, transport: { req in
            if req.url!.absoluteString.contains("get_notification_detail") {
                await gate.cancel()
                return (Data(#"{"response":{"remainingSnoozeCount":1}}"#.utf8),
                        HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            await gate.recordCommand()
            return (Data(#"{"result":true}"#.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await cpAdvanceAuto(armed, client: client,
            statusJson: statusJSON("PENDING_PLUG_IN", start: 10, dur: 50, token: "test"), now: 0,
            canAct: { await gate.active })
        XCTAssertNil(result.alert)
        let commands = await gate.commands
        XCTAssertEqual(commands, 0)
    }

    func testDecisionClockIncludesStatusReadLatency() async {
        // Deadline is 127 seconds from request start, but 117 seconds from decision time.
        let result = await cpAdvanceAuto(armed, client: client(),
            statusJson: statusJSON("ACCEPT_PENDING", start: 10, dur: 117), now: 0,
            decisionNow: { 10_000 })
        XCTAssertEqual(result.alert, .accepted)
    }
}

private actor AutoGate {
    var active = true
    var commands = 0
    func cancel() { active = false }
    func recordCommand() { commands += 1 }
}
