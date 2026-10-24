import SwiftUI
import WidgetKit
import HearthKit

/// A pending Mode/Fan choice surfaced by `ClimatePickerIntent` once the app is foregrounded.
struct ClimatePick: Identifiable, Sendable {
    let id = UUID()
    let kind: String          // "mode" | "fan"
    let options: [String]
    let current: String?
    var title: String { kind == "fan" ? "Fan mode" : "Mode" }
}

/// Shared singleton the climate picker intent talks to in-app; the view layer observes `pick` and
/// shows a confirmation dialog of the options (the iOS parity for Android's ClimatePickerActivity).
@MainActor final class ClimateGate: ObservableObject {
    static let shared = ClimateGate()
    private init() {}

    @Published var pick: ClimatePick?

    func present(kind: String, options: [String], current: String?) {
        pick = ClimatePick(kind: kind, options: options, current: current)
    }

    func choose(_ kind: String, _ option: String) {
        pick = nil
        Task { await apply(kind: kind, option: option) }
    }
    func dismiss() { pick = nil }

    private func apply(kind: String, option: String) async {
        guard let config = HaConfigStore.load(), config.hasClimate else { return }
        let service = kind == "fan" ? "set_fan_mode" : "set_hvac_mode"
        let key = kind == "fan" ? "fan_mode" : "hvac_mode"
        do {
            try await HaClient(config).callService(domain: "climate", service: service,
                                                   entityId: config.climateId, data: [key: option])
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Hearth: set \(kind) failed — \(friendlyError(error))")
        }
    }
}
