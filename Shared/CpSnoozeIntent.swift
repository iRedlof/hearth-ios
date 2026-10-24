import AppIntents
import WidgetKit
import HearthKit

/// Snooze the ChargePoint offer **in place** (no app launch) for the standard hour the auto-engine
/// uses. (The length picker used to open the app; one tap is the widget-native behaviour.)
struct CpSnoozeIntent: AppIntent {
    static var title: LocalizedStringResource { "Snooze ChargePoint offer" }
    static var isDiscoverable: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = CpSessionStore.load()
        guard session.isSignedIn else { return .result() }
        let client = CpClient(token: session.token, userId: session.userId,
                              onToken: { CpSessionStore.saveToken($0) })
        try await client.snooze(seconds: CP_AUTO_SNOOZE_SECONDS)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
        RefreshSignal.shared.bump()
        return .result()
    }
}
