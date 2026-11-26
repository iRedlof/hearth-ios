import SwiftUI
import HearthKit

/// The Connections section of the iOS Home dashboard.
/// Displays Home Assistant and ChargePoint connection status with tappable rows.
struct ConnectionsSection: View {
    private let ha: HaConnectionStatus
    private let cp: CpConnectionStatus
    private let onTap: (HomeRoute) -> Void

    init(
        ha: HaConnectionStatus,
        cp: CpConnectionStatus,
        onTap: @escaping (HomeRoute) -> Void
    ) {
        self.ha = ha
        self.cp = cp
        self.onTap = onTap
    }

    var body: some View {
        HearthGroup("Connections") {
            Button {
                onTap(.homeAssistant)
            } label: {
                HearthRow(
                    icon: "house.fill",
                    hue: .blue,
                    title: "Home Assistant",
                    subtitle: ha.label,
                    subtitleWarn: ha == .needsSignIn
                ) {
                    StatusPill(ha.label, tone: ha.tone)
                }
            }
            .buttonStyle(.plain)

            Button {
                onTap(.chargePoint)
            } label: {
                HearthRow(
                    icon: "bolt.car.fill",
                    hue: .green,
                    title: "ChargePoint",
                    subtitle: cp.label,
                    subtitleWarn: cp == .needsSignIn
                ) {
                    StatusPill(cp.label, tone: cp.tone)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Previews

#Preview("Connected + Needs Sign-In — Light") {
    ConnectionsSection(
        ha: .connected,
        cp: .needsSignIn,
        onTap: { _ in }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Connected + Needs Sign-In — Dark") {
    ConnectionsSection(
        ha: .connected,
        cp: .needsSignIn,
        onTap: { _ in }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}

#Preview("Not Set Up — Light") {
    ConnectionsSection(
        ha: .notSetUp,
        cp: .notSetUp,
        onTap: { _ in }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Not Set Up — Dark") {
    ConnectionsSection(
        ha: .notSetUp,
        cp: .notSetUp,
        onTap: { _ in }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}
