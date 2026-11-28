import SwiftUI
import HearthKit

/// Card style: how the cards look. `kind` nil: "All cards" (a ‹ › stepper walks the preview through
/// the added widgets); a kind: just that widget, which follows All cards or has its own style.
/// Every change is saved at once and redraws the widgets. Ported from Android's `CardStylePage.kt`;
/// Glass, Wallpaper and Corners are left out (see docs/CARD-STYLE-IOS.md).
@MainActor
struct CardStylePage: View {
    let kind: HomeWidgetKind?
    private let config: HaConfig?
    private let added: [HomeWidgetKind]

    @State private var follows: Bool
    @State private var style: CardStyle
    @State private var previewIndex = 0
    @State private var saveError: String?
    @StateObject private var preview = CardStylePreviewModel()
    @StateObject private var thermostat = ThermostatLiveModel()
    @Environment(\.colorScheme) private var scheme

    init(kind: HomeWidgetKind? = nil, config: HaConfig? = nil, cpSignedIn: Bool = false) {
        self.kind = kind
        self.config = config
        self.added = config.map { configuredWidgets(config: $0, chargePointSignedIn: cpSignedIn) } ?? []
        let follows = cardStyleFollowsAll(forKind: kind)
        _follows = State(initialValue: follows)
        _style = State(initialValue: follows ? CardStyleStore.global() : CardStyleStore.effectiveStyle(for: kind))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleSection
                previewSection
                if let kind { scopeSection(kind) }
                backgroundSection
                textSizeSection
                smallPrintSection
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: shown) { await loadPreview() }
        .onDisappear { thermostat.close() }
        .alert("Couldn't save card style", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Text("Card style")
            .font(HearthFont.largeTitle.font)
            .foregroundStyle(HearthColor.ink(scheme))
            .padding(.horizontal, HearthMetrics.pagePadding)
            .padding(.top, 20)
    }

    /// The real widget, as it looks now, over a wallpaper-like backdrop.
    private var previewSection: some View {
        VStack(spacing: HearthMetrics.mediumPadding) {
            WallpaperBackdrop {
                if let shown {
                    CardStylePreviewCard(kind: shown, data: preview.data[shown],
                                         thermostat: thermostat.entry, style: style)
                } else {
                    Text("Add a widget to see it here")
                        .font(HearthFont.callout.font)
                        .foregroundStyle(.white)
                        .padding(24)
                }
            }
            if kind == nil, added.count > 1, let shown {
                CardStylePreviewStepper(name: widgetDisplayName(custom: WidgetNameStore.name(for: shown),
                                                                kindDefault: shown.displayName)) { step in
                    previewIndex = cardStylePreviewIndex(previewIndex, step: step, count: added.count)
                }
            }
        }
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    /// Whose style this page changes: every card's (All cards), or just this one's.
    private func scopeSection(_ kind: HomeWidgetKind) -> some View {
        VStack(alignment: .leading, spacing: HearthMetrics.smallPadding) {
            HearthGroup("This card uses") {
                Picker("This card uses", selection: Binding(get: { follows }, set: { choose(follows: $0, for: kind) })) {
                    Text("Same as all cards").tag(true)
                    Text("Just this card").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(HearthMetrics.mediumPadding)
            }
            helper(cardStyleScopeHelper(follows: follows, name: displayName(kind)))
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: HearthMetrics.smallPadding) {
            HearthGroup("Background") {
                CardBackgroundTiles(current: style.background) { save(style.with(background: $0)) }
                if case .colour(let colour) = style.background {
                    CardColourSwatches(current: colour) { save(style.with(background: .colour($0))) }
                }
            }
            helper(cardStyleBackgroundHelper)
        }
    }

    private var textSizeSection: some View {
        HearthGroup("Text size") {
            Picker("Text size", selection: Binding(get: { style.textSize }, set: { save(style.with(textSize: $0)) })) {
                ForEach(CardTextSize.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .padding(HearthMetrics.mediumPadding)
        }
    }

    private var smallPrintSection: some View {
        HearthGroup {
            HearthRow(icon: "textformat.size.smaller", hue: .neutral, title: "Small print",
                      subtitle: "\"Checked 9:41 AM\" and details") {
                HearthSwitch(isOn: Binding(get: { style.smallPrint }, set: { save(style.with(smallPrint: $0)) }))
            }
        }
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(HearthFont.subtitle.font)
            .foregroundStyle(HearthColor.sub(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HearthMetrics.groupInset + HearthMetrics.mediumPadding)
    }

    // MARK: - Preview

    /// The widget the preview draws: this page's own, else the stepper's pick of the added widgets.
    private var shown: HomeWidgetKind? {
        if let kind { return kind }
        guard !added.isEmpty else { return nil }
        return added[cardStylePreviewIndex(previewIndex, step: 0, count: added.count)]
    }

    private func loadPreview() async {
        guard let shown else { return }
        if shown == .thermostat { thermostat.loadCache() } else { await preview.load(shown, config: config) }
    }

    private func displayName(_ kind: HomeWidgetKind) -> String {
        widgetDisplayName(custom: WidgetNameStore.name(for: kind), kindDefault: kind.displayName)
    }

    // MARK: - Saving

    /// Saves `next` where the page is editing now; a failed save puts the controls back.
    private func save(_ next: CardStyle) {
        guard next != style else { return }
        let before = style
        style = next
        do {
            try CardStyleStore.save(next, to: cardStyleSaveTarget(kind: kind, follows: follows))
        } catch {
            style = before
            saveError = error.localizedDescription
        }
    }

    /// "Same as all cards" drops the card's own style and shows the shared one; "Just this card"
    /// keeps what the controls show as the card's own.
    private func choose(follows same: Bool, for kind: HomeWidgetKind) {
        guard same != follows else { return }
        let before = (follows: follows, style: style)
        let next = same ? CardStyleStore.global() : style
        follows = same
        style = next
        do {
            if same { try CardStyleStore.clearOverride(for: kind) } else { try CardStyleStore.save(next, to: .own(kind)) }
        } catch {
            follows = before.follows
            style = before.style
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("All cards (Light)") {
    NavigationStack { CardStylePage(kind: nil) }
        .preferredColorScheme(.light)
}

#Preview("All cards (Dark)") {
    NavigationStack { CardStylePage(kind: nil) }
        .preferredColorScheme(.dark)
}

#Preview("Car (Light)") {
    NavigationStack { CardStylePage(kind: .car) }
        .preferredColorScheme(.light)
}
