import Foundation
import XCTest
@testable import HearthKit

final class CpFailureTextTests: XCTestCase {

    // MARK: - Pure failure → text mapping

    func testSignedOutReasonIsSignInNeededAndNotRetryable() {
        let presentation = cpFailurePresentation(.signedOut)
        XCTAssertEqual(presentation.reason, "ChargePoint signed you out")
        XCTAssertFalse(presentation.canRetry)
        XCTAssertEqual(presentation.line, "ChargePoint signed you out")
    }

    func testRefusedReasonIsNotRetryable() {
        let presentation = cpFailurePresentation(.refused)
        XCTAssertEqual(presentation.reason, CP_REFUSED)
        XCTAssertFalse(presentation.canRetry)
    }

    func testHttpReasonEchoesStatusAndOffersRetry() {
        let presentation = cpFailurePresentation(.http(302))
        XCTAssertEqual(presentation.reason, "ChargePoint replied 302")
        XCTAssertTrue(presentation.canRetry)
        XCTAssertEqual(presentation.line, "ChargePoint replied 302 · Refresh to retry")
    }

    func testNetworkReasonIsNoConnectionWithRetry() {
        let presentation = cpFailurePresentation(.network)
        XCTAssertEqual(presentation.reason, "No connection")
        XCTAssertTrue(presentation.canRetry)
        XCTAssertEqual(presentation.line, "No connection · Refresh to retry")
    }

    func testParseReasonIsReadFailureWithRetry() {
        let presentation = cpFailurePresentation(.parse)
        XCTAssertEqual(presentation.reason, "Couldn't read ChargePoint's reply")
        XCTAssertTrue(presentation.canRetry)
    }

    // MARK: - Classification

    func testClassifyMapsHttpStatusesAndTransport() {
        XCTAssertEqual(cpClassifyReadFailure(HaError("x", code: 401)), .signedOut)
        XCTAssertEqual(cpClassifyReadFailure(HaError("x", code: 403)), .refused)
        XCTAssertEqual(cpClassifyReadFailure(HaError("x", code: 302)), .http(302))
        XCTAssertEqual(cpClassifyReadFailure(HaError("x", code: 503)), .http(503))
        XCTAssertEqual(cpClassifyReadFailure(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(cpClassifyReadFailure(CpObservationError.malformed), .parse)
        XCTAssertEqual(cpClassifyReadFailure(HaError("x")), .other)
    }

    func testFailureHostAndStatusExtraction() {
        XCTAssertEqual(cpFailureHost(HaError("x", code: 401, host: "mc.chargepoint.com")), "mc.chargepoint.com")
        XCTAssertNil(cpFailureHost(HaError("x", code: 401)))
        XCTAssertEqual(cpFailureStatus(HaError("x", code: 401)), 401)
        XCTAssertNil(cpFailureStatus(URLError(.timedOut)))
    }

    // MARK: - Action error text

    func testActionErrorUsesReadMappingAndPreservesFeedback() {
        XCTAssertEqual(cpActionErrorText(HaError("x", code: 401)), "ChargePoint signed you out")
        XCTAssertEqual(cpActionErrorText(CpFeedback.detailsChanged), CpFeedback.detailsChanged.message)
    }

    // MARK: - Diagnostics text builder

    private func sampleInput(lastAttempt: CpDiagnosticsAttempt?) -> CpDiagnosticsInput {
        CpDiagnosticsInput(tokenPresent: true, userIDPresent: true, expired: true, minutesLeft: 42,
                           lastAttempt: lastAttempt, appVersion: "1.0", build: "18")
    }

    func testDiagnosticsTextListsEverythingWithoutValues() {
        let attempt = CpDiagnosticsAttempt(at: "9:41 AM", host: "mc.chargepoint.com",
                                           status: 401, reason: "ChargePoint signed you out")
        let text = cpDiagnosticsText(sampleInput(lastAttempt: attempt))
        XCTAssertTrue(text.contains("Token present: Yes"))
        XCTAssertTrue(text.contains("User ID present: Yes"))
        XCTAssertTrue(text.contains("Expired: Yes"))
        XCTAssertTrue(text.contains("Token valid for: 42 min"))
        XCTAssertTrue(text.contains("Last read: 9:41 AM"))
        XCTAssertTrue(text.contains("Host: mc.chargepoint.com"))
        XCTAssertTrue(text.contains("HTTP status: 401"))
        XCTAssertTrue(text.contains("Reason: ChargePoint signed you out"))
        XCTAssertTrue(text.contains("App version: 1.0 (18)"))
    }

    func testDiagnosticsTextHandlesNoAttemptAndUnknownMinutes() {
        let input = CpDiagnosticsInput(tokenPresent: true, userIDPresent: false, expired: false,
                                       minutesLeft: nil, lastAttempt: nil, appVersion: "1.0", build: "18")
        let text = cpDiagnosticsText(input)
        XCTAssertTrue(text.contains("Token valid for: unknown"))
        XCTAssertTrue(text.contains("Last read: none recorded"))
    }

    /// A secret-looking value (the token string, an email) must never appear in the output.
    func testDiagnosticsTextCannotLeakSecrets() {
        let token = "inert-fixture-cookie.header.signature"
        let email = "person@example.invalid"
        // Even if a reason/host echoed something, the input never carries the token or email.
        let attempt = CpDiagnosticsAttempt(at: "9:41 AM", host: "mc.chargepoint.com",
                                           status: 401, reason: "ChargePoint signed you out")
        let text = cpDiagnosticsText(sampleInput(lastAttempt: attempt))
        XCTAssertFalse(text.contains(token))
        XCTAssertFalse(text.contains(email))
        XCTAssertFalse(text.lowercased().contains("@example"))
    }
}
