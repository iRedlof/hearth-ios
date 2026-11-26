import Foundation

/// Utility for parsing ChargePoint JWT tokens.
public enum CpToken {
    /// Extracts the minutes remaining until expiration from a JWT token.
    /// - Parameters:
    ///   - token: The JWT token string
    ///   - now: Current date (injected for testing)
    /// - Returns: Minutes remaining, or nil if the token is malformed or expired
    public static func minutesLeft(token: String, now: Date) -> Int? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        let payload = String(parts[1])
        let padded = payload.base64PaddedString()
        guard let data = Data(base64Encoded: padded),
              let jwt = try? JSONDecoder().decode(CpJWT.self, from: data) else {
            return nil
        }

        let exp = Date(timeIntervalSince1970: jwt.exp)
        let seconds = exp.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return Int(seconds / 60)
    }
}

private struct CpJWT: Codable {
    let exp: TimeInterval
}

private extension String {
    func base64PaddedString() -> String {
        var base64 = self
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return base64
    }
}
