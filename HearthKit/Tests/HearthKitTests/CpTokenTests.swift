import Testing
import Foundation
@testable import HearthKit

@Suite("CpToken Tests")
struct CpTokenTests {
    @Test("Returns minutes left for valid token")
    func validToken() {
        // A token that expires at 2024-01-01 12:00:00 UTC (timestamp: 1704110400)
        // JWT format: header.payload.signature
        // Payload: {"exp": 1704110400}
        let payload = #"{"exp":1704110400}"#
        let payloadBase64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payloadBase64).signature"

        // Current time: 2024-01-01 11:50:00 UTC (10 minutes before expiration)
        let now = Date(timeIntervalSince1970: 1704109800)

        let minutes = CpToken.minutesLeft(token: token, now: now)
        #expect(minutes == 10)
    }

    @Test("Returns nil for expired token")
    func expiredToken() {
        let payload = #"{"exp":1704110400}"#
        let payloadBase64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payloadBase64).signature"

        // Current time: 2024-01-01 12:01:00 UTC (1 minute after expiration)
        let now = Date(timeIntervalSince1970: 1704110460)

        let minutes = CpToken.minutesLeft(token: token, now: now)
        #expect(minutes == nil)
    }

    @Test("Returns nil for malformed token")
    func malformedToken() {
        let token = "not.a.valid.jwt.token"
        let now = Date()

        let minutes = CpToken.minutesLeft(token: token, now: now)
        #expect(minutes == nil)
    }

    @Test("Returns nil for token without exp field")
    func tokenWithoutExp() {
        let payload = #"{"sub":"user123"}"#
        let payloadBase64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payloadBase64).signature"
        let now = Date()

        let minutes = CpToken.minutesLeft(token: token, now: now)
        #expect(minutes == nil)
    }

    @Test("Returns nil for empty token")
    func emptyToken() {
        let minutes = CpToken.minutesLeft(token: "", now: Date())
        #expect(minutes == nil)
    }
}
