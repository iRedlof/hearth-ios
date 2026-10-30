import AppIntents
import SwiftUI

@MainActor final class HaSetupGate: ObservableObject {
    static let shared = HaSetupGate()
    @Published var request: UUID?
    var reconnect = false
}

/// Setup widgets open connection/settings without requiring an alarm selection.
struct HaSetupIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Home Assistant settings" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Reconnect") var reconnect: Bool
    init() { reconnect = false }
    init(reconnect: Bool) { self.reconnect = reconnect }
    @MainActor func perform() async throws -> some IntentResult {
        HaSetupGate.shared.reconnect = reconnect
        HaSetupGate.shared.request = UUID()
        return .result()
    }
}
