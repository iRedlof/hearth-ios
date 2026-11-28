import SwiftUI
import AppIntents
import HearthKit

/// The Alarm card's Garage row: last reported state and one button — Open when closed, Close when
/// open, Stop while moving, none when unavailable or its reading failed. A failed command shows its
/// reason in the status line and keeps the button for a retry. The button runs the guarded door
/// command (`DoorActionIntent`) with the account scope and door-command origin rendered here.
struct AlarmGarageRowView: View {
    let garage: AlarmGarageRow
    /// The account scope the card was rendered for; empty in fixtures, which keeps the button inert.
    let scope: String
    let look: BeaconLook
    let layout: AlarmDoorRowsLayout

    private var ink: Color { Color(argb: look.ink) }
    private var needsSignIn: Bool { garage.error.map(beaconNeedsSignIn) == true }
    private var needsSettings: Bool { garage.error.map(beaconNeedsSettings) == true }
    private var hasOrigin: Bool { !scope.isEmpty && !garage.actionRevision.isEmpty }

    var body: some View {
        AlarmCompactDoorRow(icon: icon, name: garage.name,
            statusLines: alarmGarageStatusLines(garage),
            statusColor: statusColor, ink: ink, fill: Color(argb: look.chipFaint), layout: layout,
            accessibilityText: "\(garage.name), \(garage.stale ? "last known " : "")\(garage.state). \(garage.error ?? "")") {
            control
        }
    }

    private var icon: String {
        if garage.stale { return "clock" }
        guard let open = garage.open else { return "questionmark.circle" }
        return open ? "door.garage.open" : "door.garage.closed"
    }

    /// The lock row's rule: green when shut, red when open, plain ink while moving, unknown or last known.
    private var statusColor: Color {
        if garage.stale || garage.error != nil || garage.moving { return ink.opacity(0.78) }
        switch garage.open {
        case .some(false): return Color(argb: look.secure)
        case .some(true): return Color(argb: look.alert)
        case nil: return ink.opacity(0.75)
        }
    }

    @ViewBuilder private var control: some View {
        if let action = garage.action {
            if hasOrigin {
                Button(intent: DoorActionIntent(scope: scope, revision: garage.actionRevision, id: garage.entityID,
                    action: action, replacingOperation: action == .stop ? garage.replacingOperation : "")) {
                    label(action.label)
                }.buttonStyle(.plain)
            } else {
                label(action.label)
            }
        } else if needsSignIn || needsSettings {
            Button(intent: HaSetupIntent(reconnect: needsSignIn)) {
                label(needsSignIn ? "Sign in" : "Settings")
            }.buttonStyle(.plain)
        }
    }

    private func label(_ text: String) -> some View {
        AlarmCompactDoorLabel(text: text, ink: ink, fill: Color(argb: look.chip), layout: layout)
    }
}
