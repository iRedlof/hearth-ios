import SwiftUI
import WidgetKit
import HearthKit

/// Card Style settings page: global or per-widget style with live preview.
/// Allows choosing background (By state / Colour / Black), text size (Smaller / Normal / Larger),
/// and small-print visibility. Per-widget variant allows override with Undo.
@MainActor
struct CardStylePage: View {
    let kind: HomeWidgetKind?  // nil = global/all-widgets
    @State private var style: CardStyle
    @State private var hasOverride: Bool = false
    @State private var previousOverride: CardStyle?
    @State private var showUndo: Bool = false
    @Environment(\.colorScheme) private var scheme

    init(kind: HomeWidgetKind? = nil) {
        self.kind = kind
        if let kind {
            // Per-widget: load effective style and check for override
            let effective = CardStyleStore.effectiveStyle(for: kind)
            let override = CardStyleStore.override(for: kind)
            _style = State(initialValue: effective)
            _hasOverride = State(initialValue: override != nil)
        } else {
            // Global: load global style
            _style = State(initialValue: CardStyleStore.global())
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Title
                titleSection

                // Live preview mat
                previewMat

                // Caption
                captionSection

                // Per-widget override toggle (only when kind != nil)
                if kind != nil {
                    overrideSection
                }

                // Background group
                backgroundGroup

                // Text group
                textGroup

                // Small print group
                smallPrintGroup
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: style) { _, newStyle in
            saveStyle(newStyle)
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        HStack {
            Text(kind == nil ? "Card style" : "\(kind!.displayName) style")
                .font(HearthFont.largeTitle.font)
                .foregroundStyle(HearthColor.ink(scheme))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var previewMat: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Live preview widget
            HStack {
                Spacer()
                if let kind {
                    sampleWidget(for: kind)
                        .frame(width: 348, height: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    // Global preview: show Alarm as representative
                    sampleWidget(for: .alarm)
                        .frame(width: 348, height: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                Spacer()
            }
            .padding(.vertical, 24)
            .background(Color(argb: scheme == .dark ? 0xFF3D2F28 : 0xFFFFD4B3))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private var captionSection: some View {
        Text("iOS applies the style to card content. The OS controls the outer frame and corner shape.")
            .font(HearthFont.subtitle.font)
            .foregroundStyle(HearthColor.sub(scheme))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 20)
    }

    private var overrideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HearthGroupHeader(title: "This card uses")

            Picker("Style source", selection: $hasOverride) {
                Text("All widgets' style").tag(false)
                Text("Its own").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: hasOverride) { _, newHasOverride in
                handleOverrideToggle(newHasOverride)
            }

            if showUndo {
                Button {
                    undoOverride()
                } label: {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo override")
                    }
                    .font(HearthFont.button.font)
                    .foregroundStyle(HearthColor.accent(scheme))
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
    }

    private var backgroundGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HearthGroupHeader(title: "Background")

            Picker("Background", selection: Binding(
                get: { backgroundSelection },
                set: { newValue in
                    switch newValue {
                    case "byState":
                        style.background = .byState
                    case "colour":
                        style.background = .colour(.ocean)  // default to ocean
                    case "black":
                        style.background = .black
                    default:
                        break
                    }
                }
            )) {
                Text("By state").tag("byState")
                Text("Colour").tag("colour")
                Text("Black").tag("black")
            }
            .pickerStyle(.segmented)

            // Color picker when Colour is selected
            if case .colour = style.background {
                colorPicker
            }
        }
        .padding(.horizontal, 20)
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(CardColour.allCases, id: \.self) { colour in
                Button {
                    style.background = .colour(colour)
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(argb: colour.fillARGB(scheme)))
                        .frame(height: 56)
                        .overlay {
                            if case .colour(let selected) = style.background, selected == colour {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white, lineWidth: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var textGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HearthGroupHeader(title: "Text")

            Picker("Text size", selection: $style.textSize) {
                Text("Smaller").tag(CardTextSize.smaller)
                Text("Normal").tag(CardTextSize.normal)
                Text("Larger").tag(CardTextSize.larger)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
    }

    private var smallPrintGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HearthGroupHeader(title: "Show 'updated' time")

            HStack {
                Text("Small print on every card")
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                Spacer()
                HearthSwitch(isOn: $style.smallPrint)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Preview Widget

    @ViewBuilder
    private func sampleWidget(for kind: HomeWidgetKind) -> some View {
        switch kind {
        case .car:
            CarBeaconView(.sample, interactionMode: .inert, style: style)
        case .alarm:
            AlarmBeaconView(AlarmParityInputs.snapshot("disarmed"), family: .systemMedium,
                            destination: .inert, style: style)
        case .thermostat:
            ThermostatBeaconView(.sample, family: .systemMedium, style: style)
        default:
            // Other kinds don't honor CardStyle yet
            Text("Preview for \(kind.displayName)")
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(HearthColor.ink(scheme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(argb: 0xFF2A2D2E))
        }
    }

    // MARK: - Helpers

    private var backgroundSelection: String {
        switch style.background {
        case .byState: return "byState"
        case .colour: return "colour"
        case .black: return "black"
        }
    }

    private func saveStyle(_ newStyle: CardStyle) {
        if let kind, hasOverride {
            CardStyleStore.setOverride(newStyle, for: kind)
        } else if kind == nil {
            CardStyleStore.setGlobal(newStyle)
        } else {
            // Following global: save global
            CardStyleStore.setGlobal(newStyle)
        }
    }

    private func handleOverrideToggle(_ newHasOverride: Bool) {
        guard let kind else { return }

        if newHasOverride {
            // Switching to override: save current as override
            previousOverride = CardStyleStore.override(for: kind)
            CardStyleStore.setOverride(style, for: kind)
            showUndo = true
        } else {
            // Switching to global: clear override
            previousOverride = CardStyleStore.override(for: kind)
            CardStyleStore.clearOverride(for: kind)
            style = CardStyleStore.global()
            showUndo = true
        }
    }

    private func undoOverride() {
        guard let kind else { return }

        if hasOverride {
            // Undo override creation: clear and restore global
            CardStyleStore.clearOverride(for: kind)
            hasOverride = false
            style = CardStyleStore.global()
        } else {
            // Undo override removal: restore previous override
            if let previous = previousOverride {
                CardStyleStore.setOverride(previous, for: kind)
                hasOverride = true
                style = previous
            }
        }
        showUndo = false
    }
}

// MARK: - Helpers

/// Group header matching the design system.
private struct HearthGroupHeader: View {
    let title: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title)
            .font(HearthFont.groupLabel.font)
            .foregroundStyle(HearthColor.sub(scheme))
            .textCase(.uppercase)
            .padding(.top, 8)
    }
}

/// Toggle switch matching the design system.
private struct HearthSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
    }
}

// MARK: - Previews

#Preview("Global Card Style (Light)") {
    NavigationStack {
        CardStylePage(kind: nil)
    }
    .preferredColorScheme(.light)
}

#Preview("Global Card Style (Dark)") {
    NavigationStack {
        CardStylePage(kind: nil)
    }
    .preferredColorScheme(.dark)
}

#Preview("Car Card Style (Light)") {
    NavigationStack {
        CardStylePage(kind: .car)
    }
    .preferredColorScheme(.light)
}

#Preview("Car Card Style (Dark)") {
    NavigationStack {
        CardStylePage(kind: .car)
    }
    .preferredColorScheme(.dark)
}
