import SwiftUI
import HearthKit

/// Reusable confirmation sheet for house actions (leave-by, travel).
/// Shows the suggested actions (Arm / Lock / Set Eco) as explicit confirm buttons.
/// Nothing runs until the user taps confirm.
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
                            .font(.system(size: 48))
                            .foregroundStyle(HearthColor.ink(scheme))

                        Text(title)
                            .font(HearthFont.pageTitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))

                        Text("Confirm to run")
                            .font(HearthFont.subtitle.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                    .padding(.top, 20)

                    // Actions list
                    HearthGroup("Actions") {
                        ForEach(actions) { action in
                            Button {
                                onConfirm()
                            } label: {
                                HearthRow(
                                    icon: action.icon,
                                    hue: action.hue,
                                    title: action.title,
                                    subtitle: action.subtitle
                                ) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(HearthColor.sub(scheme))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
