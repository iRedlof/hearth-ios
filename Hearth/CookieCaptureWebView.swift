import HearthKit
import SwiftUI
import WebKit

/// A `WKWebView` that loads a site's own login page and reports a target cookie's value once the
/// site sets it — the iOS way to capture ChargePoint's `coulomb_sess` web session (ChargePoint is a
/// cookie session, not OAuth, so we can't use `ASWebAuthenticationSession`). The captured value is
/// persisted and sent on later REST calls.
struct CookieCaptureWebView: UIViewRepresentable {
    let url: URL
    let cookieName: String
    let onCapture: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(cookieName: cookieName, allowedDomain: "chargepoint.com", onCapture: onCapture)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let cookieName: String
        private let onCapture: (String) -> Void
        private let allowedDomain: String
        private var capturedToken: String?

        init(cookieName: String, allowedDomain: String, onCapture: @escaping (String) -> Void) {
            self.cookieName = cookieName
            self.allowedDomain = allowedDomain
            self.onCapture = onCapture
        }

        /// Keeps the login inside this web view. Without this, iOS hands the navigation to the
        /// native ChargePoint app when it is installed (its hosts claim universal links), the
        /// session cookie is never set here, and sign-in cannot complete. The rule lives in
        /// `webLoginNavigationDecision` (HearthKit), where it is tested.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            switch webLoginNavigationDecision(target: navigationAction.request.url) {
            case .keepInWebView: decisionHandler(Self.allowWithoutOpeningApps)
            case .allow: decisionHandler(.allow)
            case .block: decisionHandler(.cancel)
            }
        }

        /// WebKit's "allow, but do not try to open the link in another app" policy
        /// (`_WKNavigationActionPolicyAllowWithoutTryingAppLink`, two above `.allow`; it has no
        /// public name). It leaves the navigation itself untouched, so the login behaves exactly
        /// as before for people who do not have the ChargePoint app.
        private static let allowWithoutOpeningApps =
            WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self,
                      let cookie = cookies.first(where: {
                          let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                          return $0.name == self.cookieName &&
                              (domain == self.allowedDomain || domain.hasSuffix("." + self.allowedDomain))
                      }),
                      !cookie.value.isEmpty, cookie.value != self.capturedToken else { return }
                self.capturedToken = cookie.value
                self.onCapture(cookie.value)
            }
        }
    }
}
