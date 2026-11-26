import Foundation

/// Determines whether to show the first-run Get-started card on the iOS Home dashboard.
/// Returns true until Home Assistant is connected AND at least one widget is configured.
///
/// - Parameters:
///   - haConnected: Whether Home Assistant connection is established.
///   - widgetCount: Number of configured widgets (≥1 means user has added widgets).
/// - Returns: `true` to show the Get-started card, `false` to hide it.
public func showGetStarted(haConnected: Bool, widgetCount: Int) -> Bool {
    !(haConnected && widgetCount > 0)
}
