import Testing
import HearthKit

@Test
func test_metricsMatchSpec() {
    // Radius tokens
    #expect(HearthMetrics.groupRadius == 24)
    #expect(HearthMetrics.chipRadius == 8)
    #expect(HearthMetrics.iconTileRadius == 12)
    #expect(HearthMetrics.miniCardRadius == 22)

    // Spacing tokens
    #expect(HearthMetrics.smallPadding == 8)
    #expect(HearthMetrics.mediumPadding == 12)
    #expect(HearthMetrics.groupInset == 16)
    #expect(HearthMetrics.pagePadding == 20)

    // Row & card metrics
    #expect(HearthMetrics.rowMinHeight == 62)
    #expect(HearthMetrics.rowSidePadding == 16)
    #expect(HearthMetrics.cardRowHeight == 56)
    #expect(HearthMetrics.dividerInset == 66)

    // Widget metrics
    #expect(HearthMetrics.iconTile == 36)
    #expect(HearthMetrics.miniCardW == 174)

    // Control metrics
    #expect(HearthMetrics.switchW == 46)
    #expect(HearthMetrics.switchH == 28)
    #expect(HearthMetrics.switchThumb == 20)
    #expect(HearthMetrics.buttonH == 40)
    #expect(HearthMetrics.buttonHSmall == 32)
    #expect(HearthMetrics.chipH == 30)
}
