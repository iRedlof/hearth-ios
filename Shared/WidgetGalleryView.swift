import SwiftUI
import UIKit
import WidgetKit
import HearthKit

/// An inert production-view example at an approximate phone reference size.
/// This is an in-app layout preview, not a WidgetKit Home Screen snapshot.
struct WidgetGalleryView: View {
    @State private var kind: WidgetPreviewKind?
    @State private var reference: PhoneReference = .large
    private let unsupportedInitialKind: String?

    init() {
        let requested = UserDefaults.standard.string(forKey: "widget") ?? "car"
        let selected = WidgetPreviewKind(rawValue: requested)
        _kind = State(initialValue: selected)
        unsupportedInitialKind = selected == nil ? requested : nil
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Widget previews")
                        .font(.title2.weight(.semibold))
                    selectors
                    if let kind {
                        specimen(kind, availableWidth: max(1, geometry.size.width - 40))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if let unsupportedInitialKind {
                                Text("No preview is available for “\(unsupportedInitialKind)”.")
                            }
                            Text("Choose a widget to see its designed layout.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.body)
                        .accessibilityIdentifier("widget.preview.unavailable")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityIdentifier("widget.previews")
    }

    private var selectors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widget").font(.subheadline).foregroundStyle(.secondary)
            Menu {
                Picker("Widget", selection: $kind) {
                    if kind == nil {
                        Text("Choose a widget").tag(Optional<WidgetPreviewKind>.none)
                    }
                    ForEach(WidgetPreviewKind.allCases) { item in
                        Label(item.title, systemImage: item.symbolName).tag(Optional(item))
                    }
                }
            } label: {
                selectorLabel(kind?.title ?? "Choose a widget", symbol: kind?.symbolName)
            }
            .accessibilityLabel("Widget")
            .accessibilityValue(kind?.title ?? "None selected")
            .accessibilityIdentifier("widget.preview.kind")

            Text("Phone reference")
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
            Menu {
                Picker("Phone reference", selection: $reference) {
                    ForEach(PhoneReference.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            } label: {
                selectorLabel(reference.title, symbol: "iphone")
            }
            .accessibilityLabel("Phone reference")
            .accessibilityValue(reference.title)
            .accessibilityIdentifier("widget.preview.reference")
        }
    }

    private func selectorLabel(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 24, height: 24)
            }
            Text(title).font(.body)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func specimen(_ kind: WidgetPreviewKind, availableWidth: CGFloat) -> some View {
        let size = reference.size(for: kind.family)
        let scale = min(1, availableWidth / size.width)
        let percentage = Int((scale * 100).rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(kind.title).font(.headline)
                Spacer(minLength: 0)
                Text("Example data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(kind.family.title) · approximately \(Int(size.width)) × \(Int(size.height)) pt")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            InertWidgetPreview(content: widget(for: kind))
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .focusable(false)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Shown at \(percentage)% to fit this screen, with the full layout in proportion. Preview controls are inactive.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("widget.preview.scale")
            Text("Home Screen dimensions and rounded corners are applied by WidgetKit and may differ from this in-app example.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if kind == .car {
                Text("At larger text sizes, Car prioritizes its main status and Readings. The photo, detailed readings and controls are in the readings screen.")
                    .font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("widget.preview.example")
    }

    @ViewBuilder private func widget(for kind: WidgetPreviewKind) -> some View {
        switch kind {
        case .car:
            CarWidgetPresentation(payload: CarReadingsEntryPayload(entryID: UUID(), date: .now,
                snapshot: .sample, destination: .inert, primary: .battery(72)), family: .systemMedium)
        case .alarm: AlarmBeaconView(.sample)
        case .thermostat: ThermostatBeaconView(.sample)
        case .chargepoint: CpBeaconView(.sample)
        case .battery: BatteryView(.sample, layoutFamily: kind.family.widgetKitFamily)
        case .activity: ActivityView(.sample)
        case .lights: LightTileView(.sample)
        case .quick: QuickView(.sample)
        case .favourites: FavouritesView(.sample)
        case .doors: DoorsView(.sample)
        }
    }

    private enum PhoneReference: String, CaseIterable, Identifiable {
        case small
        case large

        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: "Small iPhone reference"
            case .large: "Large iPhone reference"
            }
        }
        func size(for family: WidgetPreviewFamily) -> CGSize {
            switch (self, family) {
            case (.small, .medium): CGSize(width: 329, height: 155)
            case (.small, .large): CGSize(width: 329, height: 345)
            case (.large, .medium): CGSize(width: 364, height: 170)
            case (.large, .large): CGSize(width: 364, height: 382)
            }
        }
    }
}

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

/// UI adapter only; family membership lives in the platform-independent catalog.
extension WidgetPreviewFamily {
    var widgetKitFamily: WidgetFamily {
        switch self {
        case .medium: .systemMedium
        case .large: .systemLarge
        }
    }
}

extension WidgetPreviewKind {
    var widgetKitFamilies: [WidgetFamily] { supportedFamilies.map(\.widgetKitFamily) }
}

#Preview { WidgetGalleryView() }
