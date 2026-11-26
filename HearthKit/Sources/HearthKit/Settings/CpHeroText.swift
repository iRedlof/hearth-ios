import Foundation

/// Formats the ChargePoint hero detail string for the connection status display.
/// - Parameters:
///   - place: The ChargePoint location name (may be nil)
///   - plugsFree: Optional count of free plugs at the location
///   - plugsTotal: Optional count of total plugs at the location
/// - Returns: A formatted detail string ("Not set up", place only, or "Place · N of M plugs free")
public func cpHeroDetail(place: String?, plugsFree: Int?, plugsTotal: Int?) -> String {
    guard let place = place else {
        return "Not set up"
    }

    let trimmed = place.trimmingCharacters(in: .whitespaces)

    // If we have both plug counts, show them
    if let free = plugsFree, let total = plugsTotal {
        return "\(trimmed) · \(free) of \(total) plugs free"
    }

    // Otherwise, show just the place
    return trimmed
}
