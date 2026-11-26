import SwiftUI
import WidgetKit
import LocalAuthentication
import HearthKit

/// Opening the garage is the one risky Doors action — gated behind Face ID (the iOS parity for
/// Android's ConfirmActivity), falling back to a confirm dialog where no biometric is enrolled.
/// `DoorOpenIntent` (`openAppWhenRun`) brings the app forward and calls `request`.
@MainActor final class GarageGate: ObservableObject {
    static let shared = GarageGate()
    private init() {}

    /// The door id awaiting an on-screen confirm (when biometric isn't available).
    @Published var confirming: String?

    func request(_ id: String) {
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Confirm to open the garage") { [weak self] ok, _ in
                Task { @MainActor in if ok { await self?.open(id) } }
            }
        } else {
            confirming = id
        }
    }

    func confirm(_ id: String) { confirming = nil; Task { await open(id) } }
    func cancel() { confirming = nil }

    private func open(_ id: String) async {
        guard let config = HaConfigStore.load() else { return }
        do {
            try await HaClient(config).callService(domain: "cover", service: "open_cover", entityId: id)
            WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.doors")
        } catch {
            print("Hearth: open garage failed — \(friendlyError(error))")
        }
    }
}
