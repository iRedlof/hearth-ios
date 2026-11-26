import SwiftUI
import HearthKit

/// Horizontal scrolling strip of widget mini-cards for the Home dashboard.
/// Displays configured widgets with problems sorted first, plus a trailing "+ Add" card.
struct YourWidgetsStrip: View {
    @Environment(\.colorScheme) private var colorScheme

    let items: [HomeWidgetItem]
    var onTap: (HomeRoute) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(sortedProblemsFirst(items)) { item in
                    widgetCard(item)
                }

                addWidgetCard
            }
            .padding(.horizontal, HearthMetrics.groupInset)
        }
    }

    // MARK: - Widget Card

    private func widgetCard(_ item: HomeWidgetItem) -> some View {
        Button {
            onTap(item.route)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Icon tile
                IconTile(
                    systemName: item.kind.icon,
                    hue: item.kind.hue
                )

                VStack(alignment: .leading, spacing: 4) {
                    // Widget name
                    Text(item.kind.displayName)
                        .font(HearthFont.rowTitle.font)
                        .foregroundStyle(HearthColor.ink(colorScheme))

                    // State line
                    Text(item.stateLine)
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(
                            item.health.sortsFirst
                                ? HearthColor.amber(colorScheme)
                                : HearthColor.sub(colorScheme)
                        )
                }

                Spacer()

                // Status pill or chevron
                HStack {
                    if item.health.sortsFirst {
                        StatusPill(statusText(item.health), tone: .warn)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HearthColor.mute(colorScheme))
                }
            }
            .padding(16)
            .frame(width: HearthMetrics.miniCardW, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: HearthMetrics.miniCardRadius)
                    .fill(HearthColor.card(colorScheme))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Widget Card

    private var addWidgetCard: some View {
        Button {
            onTap(.addWidget)
        } label: {
            VStack {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(HearthColor.mute(colorScheme))

                Text("Add")
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.sub(colorScheme))
            }
            .frame(width: HearthMetrics.miniCardW, height: 160)
            .background(
                RoundedRectangle(cornerRadius: HearthMetrics.miniCardRadius)
                    .fill(HearthColor.card(colorScheme))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func statusText(_ health: WidgetHealth) -> String {
        switch health {
        case .ok:
            return ""
        case .paused:
            return "Paused"
        case .stale:
            return "Stale data"
        case .offline:
            return "Offline"
        case .setup:
            return "Needs setup"
        case .needsSignIn:
            return "Sign in"
        case .error:
            return "Error"
        }
    }
}

// MARK: - Preview

#Preview("Light Mode") {
    YourWidgetsStrip(
        items: [
            HomeWidgetItem(
                id: "car",
                kind: .car,
                stateLine: "Ready to go",
                health: .ok,
                route: .widget(.car)
            ),
            HomeWidgetItem(
                id: "alarm",
                kind: .alarm,
                stateLine: "Stale data from 2h ago",
                health: .stale,
                route: .widget(.alarm)
            ),
            HomeWidgetItem(
                id: "lights",
                kind: .lights,
                stateLine: "3 on",
                health: .ok,
                route: .widget(.lights)
            ),
            HomeWidgetItem(
                id: "chargePoint",
                kind: .chargePoint,
                stateLine: "Sign in to view status",
                health: .needsSignIn,
                route: .widget(.chargePoint)
            ),
        ],
        onTap: { _ in }
    )
    .frame(height: 200)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    YourWidgetsStrip(
        items: [
            HomeWidgetItem(
                id: "car",
                kind: .car,
                stateLine: "Ready to go",
                health: .ok,
                route: .widget(.car)
            ),
            HomeWidgetItem(
                id: "alarm",
                kind: .alarm,
                stateLine: "Stale data from 2h ago",
                health: .stale,
                route: .widget(.alarm)
            ),
            HomeWidgetItem(
                id: "lights",
                kind: .lights,
                stateLine: "3 on",
                health: .ok,
                route: .widget(.lights)
            ),
            HomeWidgetItem(
                id: "chargePoint",
                kind: .chargePoint,
                stateLine: "Sign in to view status",
                health: .needsSignIn,
                route: .widget(.chargePoint)
            ),
        ],
        onTap: { _ in }
    )
    .frame(height: 200)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}
