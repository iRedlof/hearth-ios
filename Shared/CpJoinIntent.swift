import AppIntents
import WidgetKit
import HearthKit

/// Join the ChargePoint waitlist **in place** (no app launch) at the saved location — joining every
/// charger there, as the ChargePoint app does. (Join only appears once a location is set.) The Auto
/// pill controls the auto-engine separately, so Join no longer needs the app's "Join & auto-run" sheet.
struct CpJoinIntent: AppIntent {
    static var title: LocalizedStringResource { "Join ChargePoint waitlist" }
    static var isDiscoverable: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = CpSessionStore.load()
        guard session.isSignedIn, let location = CpSessionStore.loadLocation() else { return .result() }
        let client = CpClient(token: session.token, userId: session.userId,
                              onToken: { CpSessionStore.saveToken($0) })
        try await client.join(cpJoinBody(location))
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
        RefreshSignal.shared.bump()
        return .result()
    }
}
