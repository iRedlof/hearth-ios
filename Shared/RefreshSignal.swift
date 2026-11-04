import SwiftUI
import HearthKit

/// Relays the widgets' refresh glyph into the in-app views. The glyph runs `WidgetRefreshIntent`;
/// on the home screen that reloads the widget timeline, but in the app (Preview / Live) nothing
/// observes a widget reload — so the intent also bumps this shared signal, which the Live dashboard
/// watches to re-fetch (and show its dim-while-loading feedback). In the widget process this is a
/// harmless no-op (no view observes it there).
@MainActor final class RefreshSignal: ObservableObject {
    static let shared = RefreshSignal()
    private init() {}
    @Published var tick = 0
    @Published private(set) var cpSourceTick = 0
    @Published var thermostatRefresh: ThermostatRefreshRequest?
    func bump() { tick &+= 1 }
    func chargePointSourceChanged() { cpSourceTick &+= 1 }
    func requestThermostatRefresh(_ request: ThermostatRefreshRequest) { thermostatRefresh = request }
}
