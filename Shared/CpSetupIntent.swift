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
        CpSetupGate.shared.route = screen == "location" && CpSessionStore.load().isSignedIn ? .location : .signin
        return .result()
    }
}
