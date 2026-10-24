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

    func makeCoordinator() -> Coordinator { Coordinator(cookieName: cookieName, onCapture: onCapture) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = context.coordinator
        web.configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let cookieName: String
        private let onCapture: (String) -> Void
        private var captured = false

        init(cookieName: String, onCapture: @escaping (String) -> Void) {
            self.cookieName = cookieName
            self.onCapture = onCapture
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured,
                      let cookie = cookies.first(where: { $0.name == self.cookieName }),
                      !cookie.value.isEmpty else { return }
                self.captured = true
                self.onCapture(cookie.value)
            }
        }
    }
}
