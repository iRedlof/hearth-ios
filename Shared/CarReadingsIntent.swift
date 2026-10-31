import AppIntents
import SwiftUI
import HearthKit

@MainActor final class CarReadingsGate: ObservableObject {
    static let shared = CarReadingsGate()
    @Published var request: CarReadingsRequest?
    func open(identifier: String) { request = CarReadingsRequest(identifier: identifier) }
}

/// The complete reading remains in the App Group. Navigation carries only an opaque identifier.
struct CarReadingsIntent: AppIntent {
    static var title: LocalizedStringResource { "Open car readings" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Reading") var ticketID: String
    init() { ticketID = "" }
    init(ticketID: UUID) { self.ticketID = ticketID.uuidString }
    @MainActor func perform() async throws -> some IntentResult {
        CarReadingsGate.shared.open(identifier: ticketID)
        return .result()
    }
}

enum CarReadingsStore {
    static var store: CarReadingsTicketStore? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HaConfigStore.appGroup) else { return nil }
        return CarReadingsTicketStore(directory:
            container.appendingPathComponent("Library/Application Support/CarReadings"))
    }
}
