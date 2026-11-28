import Foundation

/// What an embedded login web view should do with a navigation.
public enum WebLoginNavigationDecision: Equatable, Sendable {
    /// Let the navigation proceed, but never hand it to another app.
    case keepInWebView
    /// Let the web view carry on untouched (page-internal schemes).
    case allow
    /// Cancel the navigation; it would leave the login (a custom app scheme, for example).
    case block
}

/// Keeps a login flow inside its web view.
///
/// iOS can hand a web navigation to another app when the destination is one of that app's
/// universal links. ChargePoint's sign-in starts on `sso.chargepoint.com` and then moves to
/// `driver.` / `na.chargepoint.com`, whose `/home*`, `/driver/*` and similar paths are claimed by
/// the native ChargePoint app. With that app installed the hand-off opened it mid-login, so the
/// session cookie was never set in Hearth and sign-in could not complete.
///
/// A login web view has no reason ever to open another app, so every web navigation is kept in
/// the web view and every non-web scheme that would launch an app is blocked.
public func webLoginNavigationDecision(target: URL?) -> WebLoginNavigationDecision {
    guard let scheme = target?.scheme?.lowercased() else { return .allow }
    switch scheme {
    case "http", "https": return .keepInWebView
    case "about", "blob", "data", "javascript": return .allow
    default: return .block
    }
}
