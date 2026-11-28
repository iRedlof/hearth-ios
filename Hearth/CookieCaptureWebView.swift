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

        /// The URL this coordinator last re-issued, so its own load is not intercepted again.
        private var reissuedURL: URL?

        /// Keeps the login inside this web view. Without this, iOS hands a cross-host navigation
        /// to the native ChargePoint app when it is installed (its hosts claim universal links),
        /// the session cookie is never set here, and sign-in cannot complete. The rule lives in
        /// `webLoginNavigationDecision` (HearthKit), where it is tested.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            let request = navigationAction.request
            let isReissue = request.url != nil && request.url == reissuedURL
            if isReissue { reissuedURL = nil }
            let decision = webLoginNavigationDecision(
                currentHost: webView.url?.host,
                target: request.url,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                method: request.httpMethod,
                isReissue: isReissue
            )
            switch decision {
            case .allow:
                decisionHandler(.allow)
            case .block:
                decisionHandler(.cancel)
            case .reloadInPlace:
                decisionHandler(.cancel)
                guard let url = request.url else { return }
                reissuedURL = url
                webView.load(URLRequest(url: url))
            }
        }

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
