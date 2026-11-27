import SwiftUI
import HearthKit

/// Reusable confirmation sheet for house actions (leave-by, travel).
/// Shows the suggested actions as plain list items describing what WILL happen.
/// Nothing runs until the user taps the single "Confirm" button.
@MainActor
struct HouseConfirmSheet: View {
    let title: String
    let actions: [HouseAction]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .font(HearthFont.iconHero.font)
                            .foregroundStyle(HearthColor.ink(scheme))

                        Text(title)
                            .font(HearthFont.pageTitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))

                        Text("Confirm to run")
                            .font(HearthFont.subtitle.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                    .padding(.top, 20)

                    // Actions list (non-interactive, describes what WILL happen)
                    HearthGroup("Actions") {
                        ForEach(actions) { action in
                            HearthRow(
                                icon: action.icon,
                                hue: action.hue,
                                title: action.title,
                                subtitle: action.subtitle
                            )
                        }
                    }

                    // Confirm button
                    Button {
                        onConfirm()
                    } label: {
                        Text("Confirm")
                            .font(HearthFont.button.font)
                            .foregroundStyle(HearthColor.onAccent(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(HearthColor.ink(scheme))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, HearthMetrics.groupInset)

                    // Cancel button
                    Button {
                        onCancel()
                    } label: {
                        Text("Not now")
                            .font(HearthFont.rowTitle.font)
                            .foregroundStyle(HearthColor.red(scheme))
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 20)
            }
            .background(HearthColor.page(scheme))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

/// A house action to confirm
struct HouseAction: Identifiable {
    let id = UUID()
    let icon: String
    let hue: TileHue
    let title: String
    let subtitle: String
}

// MARK: - Previews

#Preview("Leave-by Confirm - Light") {
    HouseConfirmSheet(
        title: "Leaving for Dentist?",
        actions: [
            HouseAction(icon: "shield.checkered", hue: .blue, title: "Arm Home alarm", subtitle: "Set to Away mode"),
            HouseAction(icon: "lock", hue: .green, title: "Lock Front door", subtitle: "Secure the entry"),
            HouseAction(icon: "thermometer", hue: .orange, title: "Set Hallway thermostat to Eco", subtitle: "Save energy while away")
        ],
        onConfirm: {},
        onCancel: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Leave-by Confirm - Dark") {
    HouseConfirmSheet(
        title: "Leaving for Dentist?",
        actions: [
            HouseAction(icon: "shield.checkered", hue: .blue, title: "Arm Home alarm", subtitle: "Set to Away mode"),
            HouseAction(icon: "lock", hue: .green, title: "Lock Front door", subtitle: "Secure the entry"),
            HouseAction(icon: "thermometer", hue: .orange, title: "Set Hallway thermostat to Eco", subtitle: "Save energy while away")
        ],
        onConfirm: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Travel Confirm - Light") {
    HouseConfirmSheet(
        title: "Trip tomorrow?",
        actions: [
            HouseAction(icon: "shield.checkered", hue: .blue, title: "Arm Away", subtitle: "Set Home alarm to Away"),
            HouseAction(icon: "thermometer", hue: .orange, title: "Thermostat low", subtitle: "Set to energy-saving mode")
        ],
        onConfirm: {},
        onCancel: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Travel Confirm - Dark") {
    HouseConfirmSheet(
        title: "Trip tomorrow?",
        actions: [
            HouseAction(icon: "shield.checkered", hue: .blue, title: "Arm Away", subtitle: "Set Home alarm to Away"),
            HouseAction(icon: "thermometer", hue: .orange, title: "Thermostat low", subtitle: "Set to energy-saving mode")
        ],
        onConfirm: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
