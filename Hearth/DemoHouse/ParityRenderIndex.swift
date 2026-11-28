#if DEBUG
import SwiftUI

/// Render harness (docs/RENDER-HARNESS.md): the widget fixtures `WidgetRenderTests` draws, read from
/// `ParityCatalog` itself so the walk follows the catalog as widgets are added and removed.
extension ParityCatalog {
    /// `-parityList`: show the ids instead of a card.
    nonisolated static func launchListsRenderIDs() -> Bool {
        ProcessInfo.processInfo.arguments.contains("-parityList")
    }

    /// Every widget fixture id, in catalog order. The `readable` entries are inert layout proofs
    /// (`AccessibleBeaconConcept`), not widgets, so they are left out.
    static func renderIDs() -> [String] {
        all().map(\.0).filter { !$0.contains("readable") }
    }
}

/// The ids as accessibility elements the UI test reads: `parityRenderCount` (how many) and
/// `parityRenderIDs` (space-separated, a few at a time so no label gets long). The test target
/// cannot link the catalog, so the app hands it the list.
struct ParityRenderIndexScreen: View {
    static let countID = "parityRenderCount"
    static let idsID = "parityRenderIDs"
    private static let idsPerRow = 12

    var body: some View {
        let ids = ParityCatalog.renderIDs()
        let rows = stride(from: 0, to: ids.count, by: Self.idsPerRow).map {
            ids[$0..<min($0 + Self.idsPerRow, ids.count)].joined(separator: " ")
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(ids.count)").font(.headline).accessibilityIdentifier(Self.countID)
                ForEach(rows, id: \.self) { row in
                    Text(row).font(.caption2.monospaced()).accessibilityIdentifier(Self.idsID)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
#endif
