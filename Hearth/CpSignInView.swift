import SwiftUI
import WebKit
import WidgetKit
import HearthKit

/// ChargePoint sign-in: load ChargePoint's own login page and capture the `coulomb_sess` cookie
/// (it's a web session, not OAuth, so this can't use `ASWebAuthenticationSession`). On capture we
/// validate the cookie with a profile call (which also names the account), mint the long-lived
/// cookie via `renewSession`, and save the session to the App Group.
struct CpSignInView: View {
    var onSignedIn: () -> Void
    @State private var phase = "Loading ChargePoint…"
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            CookieCaptureWebView(url: URL(string: "https://sso.chargepoint.com/")!,
                                 cookieName: "coulomb_sess") { token in
                Task { await validate(token) }
            }
            Text(phase).font(.caption).foregroundStyle(.secondary).padding(8)
        }
        .navigationTitle("ChargePoint")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func validate(_ token: String) async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            let json = try await CpClient(token: token, userId: 0).profile()
            guard let who = cpProfileFrom(json) else { return }   // still redirecting → wait for the next cookie
            phase = "Signing in…"
            // Save first (with the captured cookie), then renew to mint the 6-month cookie; the
            // client's onToken persists the rolled value in place.
            CpSessionStore.save(CpSession(token: token, userId: who.userId, email: who.email,
                                          renewedAt: Int64(Date().timeIntervalSince1970 * 1000)))
            let renewer = CpClient(token: token, userId: who.userId, onToken: { CpSessionStore.saveToken($0) })
            try? await renewer.renewSession()
            WidgetCenter.shared.reloadAllTimelines()
            onSignedIn()
        } catch {
            phase = friendlyError(error)
        }
    }
}
