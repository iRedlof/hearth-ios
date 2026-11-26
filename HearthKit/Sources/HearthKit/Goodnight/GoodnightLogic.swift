import Foundation

/// Determines whether Goodnight is active based on the current time and configured window.
///
/// The window is a half-open interval [startHour, endHour):
/// - `startHour` is ACTIVE (inclusive)
/// - `endHour` is INACTIVE (exclusive)
///
/// When `startHour > endHour`, the window wraps overnight (e.g., 21..5 means 21:00–23:59 and 00:00–04:59).
/// When `startHour == endHour`, the window is empty and always returns `false`.
///
/// - Parameters:
///   - now: The current date/time to check.
///   - startHour: Start hour (0–23) of the Goodnight window.
///   - endHour: End hour (0–23) of the Goodnight window.
///   - calendar: Calendar with the desired timezone (use `.current` for local time).
/// - Returns: `true` if `now` falls within the Goodnight window, `false` otherwise.
public func goodnightActive(now: Date, startHour: Int, endHour: Int, calendar: Calendar) -> Bool {
    // Extract the local hour from the date using the calendar's timezone
    let hour = calendar.component(.hour, from: now)

    // Empty window: startHour == endHour → always inactive
    if startHour == endHour {
        return false
    }

    // Non-wrap window: startHour < endHour → active when startHour <= hour < endHour
    if startHour < endHour {
        return hour >= startHour && hour < endHour
    }

    // Overnight wrap: startHour > endHour → active when hour >= startHour OR hour < endHour
    // Example: 21..5 means active during 21,22,23,0,1,2,3,4 (but not 5..20)
    return hour >= startHour || hour < endHour
}

/// Resolves the arm mode to apply, falling back to `.home` if the panel doesn't support `.night`.
///
/// - Parameters:
///   - preferred: The user's preferred arm mode.
///   - panelSupportsNight: Whether the security panel supports Night mode.
/// - Returns: `.home` if `.night` is preferred but unsupported; otherwise returns `preferred`.
public func resolveArmMode(preferred: GoodnightArmMode, panelSupportsNight: Bool) -> GoodnightArmMode {
    if preferred == .night && !panelSupportsNight {
        return .home
    }
    return preferred
}

/// Returns the light IDs to turn off: all lights minus the keep-on set, order-stable and deduplicated.
///
/// - Parameters:
///   - all: All light entity IDs to consider (may contain duplicates).
///   - keepOn: Light entity IDs to exclude from the result.
/// - Returns: Light IDs from `all` that are not in `keepOn`, preserving `all`'s order, deduplicated.
public func lightsToTurnOff(all: [String], keepOn: [String]) -> [String] {
    let keepOnSet = Set(keepOn)
    var seen = Set<String>()
    var result = [String]()
    for id in all {
        if !keepOnSet.contains(id) && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
    }
    return result
}
