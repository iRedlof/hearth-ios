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
