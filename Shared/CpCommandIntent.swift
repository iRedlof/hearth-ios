import AppIntents
import WidgetKit
import HearthKit

/// A state-specific ChargePoint manual command from the card — Accept / Snooze (60 min) / Leave /
/// Rejoin. These are the no-argument CP commands; Start/Stop (which need session/device ids) stay in
/// the ChargePoint app via "Open". After acting it reloads so the card verifies against real state.
struct CpCommandIntent: AppIntent {
    static var title: LocalizedStringResource { "ChargePoint command" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Command") var command: String

    init() {}
    init(_ command: String) { self.command = command }

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = CpSessionStore.load()
        guard session.isSignedIn else { return .result() }
        let client = CpClient(token: session.token, userId: session.userId,
                              onToken: { CpSessionStore.saveToken($0) })
        switch command {
        case "accept": try await client.accept()
        case "snooze": try await client.snooze(seconds: CP_AUTO_SNOOZE_SECONDS)
        case "leave": try await client.leave()
        case "unsnooze": try await client.unsnooze()
        case "stop":
            let status = try await client.userStatus()
            if let sessionId = cpSessionId(status) {
                try await client.stop(sessionId: sessionId, deviceId: nil, port: nil, udid: CpSessionStore.udid())
            }
        case "start":
            let status = try await client.userStatus()
            if case let .inLine(_, _, _, offer?, _) = cpWaitlistFrom(status, nil) {
                try await client.start(deviceId: offer.deviceId,
                                       connectorId: offer.port > 0 ? offer.port : nil, udid: CpSessionStore.udid())
            }
        case "still", "done":
            let status = try await client.userStatus()
            if let token = cpOfferToken(status) {
                var fault = false
                if case let .inLine(_, state, _, _, _) = cpWaitlistFrom(status, nil) { fault = (state == "CHARGING_FAULT") }
                try await client.answerStill(yes: command == "still", token: token, fault: fault)
            }
        default: break
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
        RefreshSignal.shared.bump()
        return .result()
    }
}
