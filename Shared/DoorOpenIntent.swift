import AppIntents
import HearthKit

/// Garage **Open** from the Doors widget: `openAppWhenRun` brings Hearth forward, then `GarageGate`
/// runs Face ID (or a confirm dialog) before `cover.open_cover`. `isDiscoverable = false`.
struct DoorOpenIntent: AppIntent {
    static var title: LocalizedStringResource { "Open garage" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Entity") var id: String

    init() {}
    init(_ id: String) { self.id = id }

    @MainActor
    func perform() async throws -> some IntentResult {
        GarageGate.shared.request(id)
        return .result()
    }
}
