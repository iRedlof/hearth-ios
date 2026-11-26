import Foundation
import HearthKit

/// Closes a cover (e.g., a garage door) via Home Assistant's `cover.close_cover` service.
///
/// - Parameters:
///   - id: The entity ID of the cover (e.g., "cover.garage_door").
///   - config: Home Assistant configuration for authentication and URL.
/// - Throws: `HaError` if the service call fails.
func closeCover(id: String, config: HaConfig) async throws {
    try await HaClient(config).callService(domain: "cover", service: "close_cover", entityId: id)
}

/// Turns off multiple lights via Home Assistant's `light.turn_off` service.
///
/// - Parameters:
///   - ids: The entity IDs of the lights to turn off (e.g., ["light.living_room", "light.bedroom"]).
///   - config: Home Assistant configuration for authentication and URL.
/// - Throws: `HaError` if any service call fails.
func turnOffLights(ids: [String], config: HaConfig) async throws {
    let client = HaClient(config)
    for id in ids {
        try await client.callService(domain: "light", service: "turn_off", entityId: id)
    }
}
