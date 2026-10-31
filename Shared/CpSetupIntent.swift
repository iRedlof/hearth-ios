import AppIntents
import SwiftUI

enum CpSetupRoute: String, Identifiable { case signin, location; var id: String { rawValue } }

@MainActor final class CpSetupGate: ObservableObject {
    static let shared = CpSetupGate()
    @Published var route: CpSetupRoute?
}

/// Widget setup opens the relevant ChargePoint screen even without a Home Assistant connection.
struct CpSetupIntent: AppIntent {
    static var title: LocalizedStringResource { "Configure ChargePoint" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Screen") var screen: String
    init() {}
    init(_ screen: String) { self.screen = screen }
    @MainActor func perform() async throws -> some IntentResult {
        #if DEBUG
        // The isolated ownership harness exercises local/provider commands, never real web sign-in.
        if CpSessionStore.fixtureActive { return .result() }
        #endif
        CpSetupGate.shared.route = screen == "location" && (try? CpSessionStore.context().session.isSignedIn) == true ? .location : .signin
        return .result()
    }
}
