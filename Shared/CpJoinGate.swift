import SwiftUI
import WidgetKit
import HearthKit

/// The Join-waitlist flow. Android asks first ("Join & auto-run" vs "Just join"); on iOS the card's
/// Join opens the app and this gate shows that choice, then joins every charger at the saved location
/// (as the ChargePoint app does) and arms the auto engine if chosen.
@MainActor final class CpJoinGate: ObservableObject {
    static let shared = CpJoinGate()
    private init() {}

    @Published var asking = false

    func request() { asking = CpSessionStore.loadLocation() != nil }
    func cancel() { asking = false }

    func join(auto: Bool) {
        asking = false
        Task { await perform(auto: auto) }
    }

    private func perform(auto: Bool) async {
        let session = CpSessionStore.load()
        guard session.isSignedIn, let location = CpSessionStore.loadLocation() else { return }
        let client = CpClient(token: session.token, userId: session.userId,
                              onToken: { CpSessionStore.saveToken($0) })
        do {
            try await client.join(cpJoinBody(location))
            if auto {
                let armed = cpArmForCommand(CpSessionStore.loadRun(), .join, autoRun: true,
                                            now: Int64(Date().timeIntervalSince1970 * 1000))
                CpSessionStore.saveRun(armed)
                CpNotify.requestPermission()
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
            RefreshSignal.shared.bump()
        } catch {
            print("Hearth: join failed — \(friendlyError(error))")
        }
    }
}
