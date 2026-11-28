import SwiftUI
import HearthKit

/// Tiles in rows of two. An odd last tile keeps its half of the row, as pictured.
struct BeaconTileGrid<Cell: View>: View {
    let tiles: [PanelTile]
    @ViewBuilder let cell: (PanelTile) -> Cell

    private var rows: [[PanelTile]] { panelRows(tiles, columns: PanelLimits.tileColumns) }

    var body: some View {
        VStack(spacing: PanelMetrics.gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: PanelMetrics.gridSpacing) {
                    ForEach(row) { cell($0) }
                    ForEach(row.count..<PanelLimits.tileColumns, id: \.self) { _ in emptyCell }
                }
            }
        }
    }

    /// Holds a column's width without adding any height to its row.
    private var emptyCell: some View {
        Color.clear.frame(maxWidth: .infinity).frame(height: 0).accessibilityHidden(true)
    }
}
