import AppIntents
import WidgetKit
import HearthKit

/// A state-specific ChargePoint manual command from the card — Accept / Snooze (60 min) / Leave /
/// Rejoin. These are the no-argument CP commands; Start/Stop (which need session/device ids) stay in
/// the ChargePoint app via "Open". After acting it reloads so the card verifies against real state.
struct CpCommandIntent: AppIntent {
    static var title: LocalizedStringResource { "ChargePoint command" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Command") var command: String

    init() {}
    init(_ command: String) { self.command = command }

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = CpSessionStore.load()
        guard session.isSignedIn else { return .result() }
        let client = CpClient(token: session.token, userId: session.userId,
                              onToken: { CpSessionStore.saveToken($0) })
        switch command {
        case "accept": try await client.accept()
        case "snooze": try await client.snooze(seconds: CP_AUTO_SNOOZE_SECONDS)
        case "leave": try await client.leave()
        case "unsnooze": try await client.unsnooze()
        default: break
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
        RefreshSignal.shared.bump()
        return .result()
    }
}
