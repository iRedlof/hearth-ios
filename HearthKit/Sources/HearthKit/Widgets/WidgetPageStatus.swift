import Foundation

/// The status a healthy, set-up widget page shows. Only a preview drawn from the person's own
/// data may sit above this line (see `widgetPreviewCaption`).
let widgetPageOnHomeScreen = "On your home screen"

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
            return "\(widgetPageOnHomeScreen) · updated \(fresh)"
        } else {
            return widgetPageOnHomeScreen
        }
    }
}

/// Where the preview card on a widget page gets what it draws.
public enum WidgetPreviewSource: Equatable, Sendable {
    /// The person's own current data.
    case live
    /// Their own data is on its way; nothing made-up is shown as theirs meanwhile.
    case loading
    /// Made-up sample data, labelled as an example.
    case example
}

/// A preview is live only for a set-up widget whose page can load its data. Until that data
/// arrives it is `loading`, never the sample: a sample under "On your home screen" reads as real.
public func widgetPreviewSource(isSetUp: Bool, supportsLive: Bool, hasLiveData: Bool) -> WidgetPreviewSource {
    guard isSetUp, supportsLive else { return .example }
    return hasLiveData ? .live : .loading
}

/// The line under the preview. The "On your home screen" claim is kept only for a live preview;
/// warnings and the not-set-up line pass through unchanged.
public func widgetPreviewCaption(_ source: WidgetPreviewSource, status: String) -> String {
    guard status.hasPrefix(widgetPageOnHomeScreen) else { return status }
    switch source {
    case .live: return status
    case .loading: return "Loading your widget…"
    case .example: return "Example · your widget shows your own data"
    }
}
