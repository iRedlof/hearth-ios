import SwiftUI
import WidgetKit
import HearthKit

/// Add-a-widget gallery: categorized browser of available widgets with specimen previews.
struct AddWidgetGallery: View {
    private let config: HaConfig?
    private let cpSignedIn: Bool
    private let onPick: (HomeWidgetKind) -> Void
    private let onConnectHA: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(
        config: HaConfig?,
        cpSignedIn: Bool,
        onPick: @escaping (HomeWidgetKind) -> Void,
        onConnectHA: @escaping () -> Void
    ) {
        self.config = config
        self.cpSignedIn = cpSignedIn
        self.onPick = onPick
        self.onConnectHA = onConnectHA
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top banner when HA not set up
                if config == nil || (config?.baseUrl.isEmpty ?? true) {
                    connectBanner
                }

                // Categories
                ForEach(AddCategory.allCases, id: \.rawValue) { category in
                    categorySection(category)
                }
            }
            .padding(16)
        }
        .background(HearthColor.page(scheme).ignoresSafeArea())
        .navigationTitle("Add a widget")
    }

    // MARK: - Connect Banner

    private var connectBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most of these need Home Assistant")
                .font(HearthFont.rowTitle.font)
                .foregroundStyle(HearthColor.ink(scheme))

            Button("Connect") {
                onConnectHA()
            }
            .hearthInk()
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(HearthColor.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius, style: .continuous))
    }

    // MARK: - Category Section

    private func categorySection(_ category: AddCategory) -> some View {
        HearthGroup(category.rawValue) {
            ForEach(widgetsInCategory(category), id: \.self) { kind in
                widgetCard(kind)
            }
        }
    }

    // MARK: - Widget Card

    private func widgetCard(_ kind: HomeWidgetKind) -> some View {
        Button {
            onPick(kind)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Mini specimen (small preview)
                if let previewKind = previewKind(for: kind) {
                    miniSpecimen(previewKind)
                        .frame(width: WidgetThumbnail.slot.width, height: WidgetThumbnail.slot.height)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Title, description, and status chip in one left-aligned column.
                // The chip sits BELOW the description so "Needs Home Assistant" /
                // "Needs ChargePoint" gets the full text-column width (never truncates to
                // "Needs…") without starving the title/description into per-word wrapping.
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.displayName)
                        .font(HearthFont.rowTitle.font)
                        .foregroundStyle(HearthColor.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(description(for: kind))
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    chip(for: kind)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, HearthMetrics.rowSidePadding)
            .padding(.vertical, HearthMetrics.mediumPadding)
            .frame(minHeight: HearthMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mini Specimen

    @ViewBuilder
    private func miniSpecimen(_ kind: WidgetPreviewKind) -> some View {
        InertWidgetPreview(content: widget(for: kind))
            .background(HearthColor.tint(scheme))
    }

    @ViewBuilder
    private func widget(for kind: WidgetPreviewKind) -> some View {
        switch kind {
        case .car:
            CarWidgetPresentation(payload: CarParityInputs.productionPayload("parked"))
                .widgetThumbnail()
        case .alarm:
            AlarmBeaconView(AlarmParityInputs.snapshot("disarmed"))
                .widgetThumbnail()
        case .thermostat:
            ThermostatBeaconView(ThermostatParityInputs.payload("auto"))
                .widgetThumbnail()
        case .chargepoint:
            CpBeaconView(.sample)
                .widgetThumbnail()
        case .battery:
            BatteryView(.sample, layoutFamily: .systemMedium)
                .widgetThumbnail()
        case .activity:
            ActivityView(.sample)
                .widgetThumbnail()
        case .lights:
            LightTileView(.sample)
                .widgetThumbnail()
        case .quick:
            QuickView(.sample)
                .widgetThumbnail()
        case .favourites:
            FavouritesView(.sample)
                .widgetThumbnail()
        case .doors:
            DoorsView(.sample)
                .widgetThumbnail()
        }
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(for kind: HomeWidgetKind) -> some View {
        let chip = addWidgetChip(kind: kind, config: config ?? .empty, cpSignedIn: cpSignedIn)
        switch chip {
        case .added:
            StatusPill("Added", tone: .ok)
        case .ready:
            StatusPill("Ready to set up", tone: .ok)
        case .needsHA:
            StatusPill("Needs Home Assistant", tone: .neutral)
        case .needsCP:
            StatusPill("Needs ChargePoint", tone: .neutral)
        }
    }

    // MARK: - Helpers

    private func widgetsInCategory(_ category: AddCategory) -> [HomeWidgetKind] {
        HomeWidgetKind.allCases.filter { addWidgetCategory($0) == category }
    }

    private func description(for kind: HomeWidgetKind) -> String {
        switch kind {
        case .car:
            return "Car status and readings"
        case .alarm:
            return "Arm and disarm your home alarm"
        case .thermostat:
            return "Control your thermostat"
        case .doors:
            return "Monitor and control doors"
        case .quick:
            return "Quick actions and scripts"
        case .lights:
            return "Control your lights"
        case .favourites:
            return "Favourite scenes and automations"
        case .activity:
            return "Recent activity and events"
        case .battery:
            return "Battery levels for all devices"
        case .chargePoint:
            return "EV charging status and control"
        }
    }

    private func previewKind(for kind: HomeWidgetKind) -> WidgetPreviewKind? {
        switch kind {
        case .car: return .car
        case .alarm: return .alarm
        case .thermostat: return .thermostat
        case .doors: return .doors
        case .quick: return .quick
        case .lights: return .lights
        case .favourites: return .favourites
        case .activity: return .activity
        case .battery: return .battery
        case .chargePoint: return .chargepoint
        }
    }
}

// MARK: - Empty HaConfig

private extension HaConfig {
    static let empty = HaConfig(baseUrl: "", token: "", entityId: "", refreshToken: "")
}

// MARK: - Inert Preview Wrapper

/// Blocks preview input at the native host without changing the production controls' enabled look.
private struct InertWidgetPreview<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> InertWidgetPreviewController {
        let controller = InertWidgetPreviewController(rootView: rootView(context: context))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.accessibilityElementsHidden = true
        return controller
    }

    func updateUIViewController(_ controller: InertWidgetPreviewController, context: Context) {
        controller.rootView = rootView(context: context)
    }

    private func rootView(context: Context) -> AnyView {
        AnyView(content
            .environment(\.colorScheme, context.environment.colorScheme)
            .environment(\.dynamicTypeSize, context.environment.dynamicTypeSize)
            .environment(\.layoutDirection, context.environment.layoutDirection)
            .allowsHitTesting(false)
            .accessibilityHidden(true))
    }
}

private final class InertWidgetPreviewController: UIHostingController<AnyView> {
    override var canBecomeFirstResponder: Bool { false }
    override var keyCommands: [UIKeyCommand]? { [] }
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool { false }
}

// MARK: - Previews

#Preview("Connected with some added") {
    NavigationStack {
        AddWidgetGallery(
            config: HaConfig(
                baseUrl: "https://ha.example.com",
                token: "token",
                entityId: "alarm_control_panel.home",
                refreshToken: "refresh",
                climateId: "climate.living_room",
                scriptIdsJson: "[\"script.one\"]"
            ),
            cpSignedIn: true,
            onPick: { _ in },
            onConnectHA: {}
        )
    }
}

#Preview("Nothing connected") {
    NavigationStack {
        AddWidgetGallery(
            config: nil,
            cpSignedIn: false,
            onPick: { _ in },
            onConnectHA: {}
        )
    }
}

#Preview("Dark mode") {
    NavigationStack {
        AddWidgetGallery(
            config: HaConfig(
                baseUrl: "https://ha.example.com",
                token: "token",
                entityId: "alarm_control_panel.home",
                refreshToken: "refresh"
            ),
            cpSignedIn: false,
            onPick: { _ in },
            onConnectHA: {}
        )
    }
    .preferredColorScheme(.dark)
}

// MARK: - Thumbnails

/// A widget drawn at its real size and then shrunk as a picture. Scaling alone (the old
/// `.scaleEffect(0.38)`) left the widget laying itself out inside the 60pt slot first, which
/// produced the squashed, unreadable thumbnails.
enum WidgetThumbnail {
    /// The slot every row reserves, so titles line up whatever the widget's shape.
    static let slot = CGSize(width: 96, height: 60)

    /// The medium Home Screen widget size on a 393pt-wide iPhone.
    static let natural = CGSize(width: 364, height: 170)

    static let scale = min(slot.width / natural.width, slot.height / natural.height)
}

private extension View {
    func widgetThumbnail() -> some View {
        widgetContainer(size: WidgetThumbnail.natural)
            .scaleEffect(WidgetThumbnail.scale)
            .frame(width: WidgetThumbnail.natural.width * WidgetThumbnail.scale,
                   height: WidgetThumbnail.natural.height * WidgetThumbnail.scale)
    }
}
