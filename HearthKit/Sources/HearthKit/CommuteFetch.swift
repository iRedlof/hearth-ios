import Foundation

/// The HA commute sensor template that returns `true|false` for charge_now and signin_needed.
private let COMMUTE_TEMPLATE = """
{{ is_state('binary_sensor.commute_charge_now','on') }}|{{ is_state('binary_sensor.commute_signin_needed','on') }}
"""

/// Fetches the two commute booleans from Home Assistant's template sensors.
///
/// - Parameters:
///   - config: The Home Assistant configuration (must be `carReady` to fetch).
///   - now: The current time (for the `lastHeard` timestamp on successful fetch).
///   - read: Optional transport seam for testing (bypasses HaClient).
/// - Returns: A tuple `(chargeNow: Bool, signinNeeded: Bool, lastHeard: Date)` on success, `nil` on failure.
///
/// This mirrors the fetch pattern used by `fetchBatterySnapshot` and `fetchLightsSnapshot`.
/// It renders the template via `HaClient.template()`, parses the result with `parseCommuteSensors`,
/// and returns the two booleans plus the fetch timestamp.
public func fetchCommuteSensors(
    _ config: HaConfig?,
    now: Date = Date(),
    read: (@Sendable () async throws -> String)? = nil
) async -> (chargeNow: Bool, signinNeeded: Bool, lastHeard: Date)? {
    guard let config, config.carReady else { return nil }

    do {
        let body: String
        if let read {
            body = try await read()
        } else {
            body = try await HaClient(config).template(COMMUTE_TEMPLATE)
        }

        guard let parsed = parseCommuteSensors(body) else { return nil }
        return (chargeNow: parsed.chargeNow, signinNeeded: parsed.signinNeeded, lastHeard: now)
    } catch {
        return nil
    }
}
