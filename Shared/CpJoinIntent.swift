import AppIntents
import WidgetKit
import HearthKit

/// Join the ChargePoint waitlist **in place** (no app launch) at the saved location — joining every
/// charger there, as the ChargePoint app does. (Join only appears once a location is set.) The Auto
/// pill controls the auto-engine separately, so Join no longer needs the app's "Join & auto-run" sheet.
struct CpJoinIntent: AppIntent {
    static var title: LocalizedStringResource { "Join ChargePoint waitlist" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Rendered origin", default: "") var origin: String

    init() {}
    init(origin: String) { self.origin = origin }

    @MainActor
    func perform() async throws -> some IntentResult {
        await CpWidgetOperation.perform("join", origin: origin)
        return .result()
    }
}
