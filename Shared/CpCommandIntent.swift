import AppIntents
import WidgetKit
import HearthKit

/// Manual keys use the same tested runtime, preserving Auto mode and recording command feedback.
struct CpCommandIntent: AppIntent {
    static var title: LocalizedStringResource { "ChargePoint command" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Command") var command: String

    init() {}
    init(_ command: String) { self.command = command }

    @MainActor
    func perform() async throws -> some IntentResult {
        await CpWidgetOperation.perform(command)
        return .result()
    }
}
