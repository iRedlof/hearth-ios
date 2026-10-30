import SwiftUI
import UIKit
import AuthenticationServices
import WidgetKit
import HearthKit

/// Browser-based Home Assistant sign-in — the same OAuth (IndieAuth) flow the Android app uses.
/// HA hosts its own login page, which we open in an `ASWebAuthenticationSession`; on success HA
/// redirects to `hearth://auth-callback?code=…&state=…`, and we exchange the code for a refresh
/// token (persisted to the App Group so the widget can use it too). No long-lived token to paste.
///
/// This view lives in the app target (not `Shared/`) because `ASWebAuthenticationSession`
/// presentation and `UIApplication` are unavailable in the widget extension.
struct SignInView: View {
    var onSignedIn: () -> Void

    @StateObject private var auth = AuthCoordinator()
    @State private var urlText = "https://ha.iredlof-nas.synology.me/"

    init(initialURL: String? = nil, onSignedIn: @escaping () -> Void) {
        self.onSignedIn = onSignedIn
        if let initialURL, !initialURL.isEmpty { _urlText = State(initialValue: initialURL) }
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "house.lodge.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Connect to Home Assistant")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Sign in with your Home Assistant account — the same browser login as the Android app. There's no long-lived token to copy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("HOME ASSISTANT URL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("https://home.example.com", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { auth.signIn(base: urlText) }
            }
            .padding(.top, 8)

            Button {
                auth.signIn(base: urlText)
            } label: {
                HStack(spacing: 8) {
                    if auth.busy { ProgressView().tint(.white) }
                    Text(auth.busy ? "Opening…" : "Sign in")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(auth.busy || urlText.isEmpty)

            if !auth.status.isEmpty {
                Text(auth.status)
                    .font(.footnote)
                    .foregroundStyle(auth.isError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(28)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { auth.onSignedIn = onSignedIn }
    }
}

/// Owns the `ASWebAuthenticationSession` and the sign-in state. A `@MainActor` reference type so the
/// mutable UI state (`busy`/`status`) is actor-isolated — this avoids the Swift 6 "mutating captured
/// `self`" trouble you hit when driving an escaping completion handler from a SwiftUI `struct` View.
@MainActor
final class AuthCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var busy = false
    @Published var status = ""
    @Published var isError = false
    var onSignedIn: (() -> Void)?

    private var session: ASWebAuthenticationSession?

    func signIn(base rawBase: String) {
        guard !busy else { return }
        var base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard base.hasPrefix("https://"), URL(string: base) != nil else {
            set("Enter an https:// address, e.g. https://home.example.com", error: true); return
        }
        let state = UUID().uuidString
        guard let authURL = HaAuth.authorizeURL(base, state: state) else {
            set("That URL doesn't look valid.", error: true); return
        }
        set("Opening your Home Assistant login…", error: false)
        busy = true

        // The completion closure runs outside the main actor; extract only Sendable values
        // (URL/Bool/String) and hop back onto the main actor before touching @Published state.
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "hearth") { [weak self] callback, error in
            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            let failed = error != nil && !cancelled
            Task { @MainActor in
                self?.finish(base: base, state: state, callback: callback, cancelled: cancelled, failed: failed)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false   // reuse any existing HA browser cookie
        self.session = session
        session.start()
    }

    private func finish(base: String, state: String, callback: URL?, cancelled: Bool, failed: Bool) {
        if cancelled { busy = false; set("Sign-in cancelled.", error: false); return }
        if failed {
            busy = false; set("Couldn't open the login page. Check the URL and your connection.", error: true); return
        }
        guard let callback,
              let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
              comps.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            // A mismatched/absent `state` means the response wasn't the one we initiated — reject it.
            busy = false; set("The sign-in response was invalid. Please try again.", error: true); return
        }
        Task { await exchange(base: base, code: code) }
    }

    private func exchange(base: String, code: String) async {
        do {
            let tokens = try await HaAuth.exchange(base, code)
            guard let refresh = tokens.refresh, !refresh.isEmpty else {
                busy = false
                set("Home Assistant didn't return a session token. Check that the dashboard client is allowed.", error: true)
                return
            }
            var cfg = HaConfigStore.load() ?? HaConfig(baseUrl: "", token: "", entityId: "")
            cfg.baseUrl = base
            cfg.refreshToken = refresh
            cfg.token = ""                       // OAuth supersedes any long-lived token
            try HaConfigStore.save(cfg)
            await HaAuth.shared.forget()          // drop any stale cached access token
            WidgetCenter.shared.reloadAllTimelines()
            busy = false
            set("Signed in.", error: false)
            onSignedIn?()
        } catch {
            busy = false
            set(friendlyError(error), error: true)
        }
    }

    private func set(_ text: String, error: Bool) { status = text; isError = error }

    // Called by the system on the main thread to find a window to present over.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return windows.first(where: { $0.isKeyWindow }) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
