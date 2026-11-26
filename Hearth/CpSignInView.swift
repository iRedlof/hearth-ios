import SwiftUI
import WebKit
import WidgetKit
import HearthKit

/// Candidate cookies stay isolated until the captured sign-in attempt validates profile and renewal.
struct CpSignInView: View {
    let expected: CpSettingsOrigin?
    var onSignedIn: () -> Void
    @State private var owner: CpSignInOwner?
    @State private var phase = "Loading ChargePoint…"
    @State private var latestToken = ""
    @State private var unavailable = false

    init(expected: CpSettingsOrigin? = nil, onSignedIn: @escaping () -> Void) {
        self.expected = expected ?? (try? CpSessionStore.context().settingsOrigin)
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        VStack(spacing: 0) {
            if let owner {
                CookieCaptureWebView(url: URL(string: "https://sso.chargepoint.com/")!, cookieName: "coulomb_sess") { token in
                    latestToken = token
                    Task { await validate(token, owner: owner) }
                }.id(owner.attemptID)
            } else if unavailable {
                ContentUnavailableView("ChargePoint unavailable", systemImage: "exclamationmark.triangle",
                    description: Text("Shared storage could not be opened. Resetting signs ChargePoint out."))
                Button("Reset ChargePoint storage") {
                    do {
                        try CpSessionStore.recoverSignedOut()
                        onSignedIn()
                    } catch { phase = friendlyError(error) }
                }
            } else { ProgressView() }
            Text(phase).font(.caption).foregroundStyle(.secondary).padding(8)
        }
        .navigationTitle("ChargePoint")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                guard let expected, let attempt = try CpSessionStore.repository().store.beginSignIn(expected: expected) else {
                    phase = "Details changed · Reopen sign in"
                    unavailable = expected == nil
                    return
                }
                owner = attempt
            } catch { phase = friendlyError(error); unavailable = true }
        }
        .onDisappear {
            if let owner { try? CpSessionStore.repository().store.cancelSignIn(owner: owner) }
        }
    }

    @MainActor private func validate(_ token: String, owner captured: CpSignInOwner) async {
        guard owner == captured else { return }
        phase = "Signing in…"
        do {
            let accepted = try await CpSessionStore.runtime().signIn(owner: captured, token: token)
            guard owner == captured, latestToken == token,
                  try CpSessionStore.context().context.accountGeneration == accepted.context.accountGeneration else { return }
            WidgetCenter.shared.reloadAllTimelines()
            onSignedIn()
        } catch {
            guard owner == captured, latestToken == token else { return }
            phase = friendlyError(error)
        }
    }
}
