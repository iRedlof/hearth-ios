import Foundation

/// What an embedded login web view should do with a navigation.
public enum WebLoginNavigationDecision: Equatable, Sendable {
    /// Let the web view carry on.
    case allow
    /// Cancel the navigation and load the same URL programmatically in the same web view.
    case reloadInPlace
    /// Cancel the navigation; it would leave the login (a custom app scheme, for example).
    case block
}

/// Keeps a login flow inside its web view.
///
/// iOS hands a main-frame navigation to another app when the destination host differs from the
/// current page's host and that host claims the URL as a universal link. ChargePoint's sign-in
/// starts on `sso.chargepoint.com` and then moves to `driver.` / `na.chargepoint.com`, whose
/// `/home*`, `/driver/*` and similar paths are claimed by the native ChargePoint app. With that app
/// installed the hand-off opened it mid-login, so the session cookie was never set in Hearth and
/// sign-in could not complete. A URL loaded programmatically is never handed to another app, so
/// every cross-host main-frame GET is cancelled and re-issued in place.
///
/// - Parameters:
///   - currentHost: Host of the page the web view is showing now; `nil` before the first load.
///   - target: Destination of the navigation.
///   - isMainFrame: Whether the navigation targets the main frame. Pass `true` when the target
///     frame is unknown (a link that wants a new window), so it opens in the same web view.
///   - method: HTTP method of the request; `nil` is treated as GET.
///   - isReissue: `true` when this is the load the caller issued for an earlier `.reloadInPlace`.
public func webLoginNavigationDecision(
    currentHost: String?,
    target: URL?,
    isMainFrame: Bool,
    method: String?,
    isReissue: Bool
) -> WebLoginNavigationDecision {
    guard let target, let scheme = target.scheme?.lowercased() else { return .allow }
    guard scheme == "http" || scheme == "https" else {
        // Page-internal schemes are harmless; anything else would leave the login.
        return ["about", "blob", "data", "javascript"].contains(scheme) ? .allow : .block
    }
    guard isMainFrame, !isReissue else { return .allow }
    guard (method ?? "GET").uppercased() == "GET" else { return .allow }
    guard let currentHost, let targetHost = target.host else { return .allow }
    return currentHost.lowercased() == targetHost.lowercased() ? .allow : .reloadInPlace
}
