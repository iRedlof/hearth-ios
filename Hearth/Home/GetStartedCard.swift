import SwiftUI
import HearthKit

/// First-run Get-started card shown until Home Assistant is connected AND at least one widget is configured.
/// Displays two numbered steps with completion indicators and action buttons.
struct GetStartedCard: View {
    private let haConnected: Bool
    private let hasWidget: Bool
    private let onConnect: () -> Void
    private let onAddWidget: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(
        haConnected: Bool,
        hasWidget: Bool,
        onConnect: @escaping () -> Void,
        onAddWidget: @escaping () -> Void
    ) {
        self.haConnected = haConnected
        self.hasWidget = hasWidget
        self.onConnect = onConnect
        self.onAddWidget = onAddWidget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Get started")
                    .font(HearthFont.cardHeading.font)
                    .foregroundStyle(HearthColor.ink(scheme))

                Text("2 steps · this card goes away when you finish")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
            }

            VStack(alignment: .leading, spacing: 16) {
                // Step 1: Connect Home Assistant
                HStack(alignment: .top, spacing: 12) {
                    stepIndicator(number: 1, done: haConnected)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Home Assistant")
                            .font(HearthFont.rowTitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))

                        if !haConnected {
                            Button("Connect") {
                                onConnect()
                            }
                            .hearthInk()
                        }
                    }
                }

                // Step 2: Add a widget
                HStack(alignment: .top, spacing: 12) {
                    stepIndicator(number: 2, done: hasWidget)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a widget")
                            .font(HearthFont.rowTitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))

                        if haConnected && !hasWidget {
                            Button("Add widget") {
                                onAddWidget()
                            }
                            .hearthInk()
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HearthColor.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius, style: .continuous))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    @ViewBuilder
    private func stepIndicator(number: Int, done: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? HearthColor.green(scheme) : HearthColor.tint(scheme))
                .frame(width: 28, height: 28)

            if done {
                Image(systemName: "checkmark")
                    .font(HearthFont.callout.font.weight(.bold))
                    .foregroundStyle(HearthColor.onAccent(scheme))
            } else {
                Text("\(number)")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.mute(scheme))
            }
        }
    }
}

// MARK: - Previews

#Preview("Step 1 incomplete — Light") {
    GetStartedCard(
        haConnected: false,
        hasWidget: false,
        onConnect: {},
        onAddWidget: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Step 1 incomplete — Dark") {
    GetStartedCard(
        haConnected: false,
        hasWidget: false,
        onConnect: {},
        onAddWidget: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}

#Preview("Step 1 done — Light") {
    GetStartedCard(
        haConnected: true,
        hasWidget: false,
        onConnect: {},
        onAddWidget: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Step 1 done — Dark") {
    GetStartedCard(
        haConnected: true,
        hasWidget: false,
        onConnect: {},
        onAddWidget: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}
