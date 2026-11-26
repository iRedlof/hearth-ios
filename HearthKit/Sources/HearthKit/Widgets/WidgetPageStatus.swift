import Foundation

/// Returns the status line for a widget settings page based on health, freshness, and setup state.
public func widgetPageStatus(health: WidgetHealth, fresh: String?, isSetUp: Bool) -> String {
    // Not set up case
    if !isSetUp || health == .setup {
        return "Example · yours appears after setup"
    }

    // Health-based warnings (take precedence over freshness)
    switch health {
    case .error:
        return "Couldn't update · check Home Assistant connection"
    case .needsSignIn:
        return "Sign in to Home Assistant to update"
    case .stale:
        return "Hasn't updated in a while · check Home Assistant connection"
    case .offline:
        return "Home Assistant is offline"
    case .paused:
        return "Updates paused"
    case .ok, .setup:
        // OK: show "On your home screen" with optional freshness
        if let fresh {
            return "On your home screen · updated \(fresh)"
        } else {
            return "On your home screen"
        }
    }
}
