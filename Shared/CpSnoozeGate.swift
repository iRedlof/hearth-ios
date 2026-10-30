import SwiftUI
import WidgetKit
import HearthKit

/// Snooze with a length choice (10 / 30 / 60 min, like Android's snooze sheet). The card's Snooze
/// key opens the app and this gate asks the length, then calls `snoozeV2`.
@MainActor final class CpSnoozeGate: ObservableObject {
    static let shared = CpSnoozeGate()
    private init() {}

    @Published var asking = false

    func request() { asking = true }
    func cancel() { asking = false }

    func snooze(minutes: Int) {
        asking = false
        Task { await perform(minutes) }
    }

    private func perform(_ minutes: Int) async {
        await CpWidgetOperation.perform("snooze", snoozeSeconds: minutes * 60)
    }
}
