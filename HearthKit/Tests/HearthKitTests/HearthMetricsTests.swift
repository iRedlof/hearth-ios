import Testing
import HearthKit

@Test
func test_metricsMatchSpec() {
    #expect(HearthMetrics.groupRadius == 24)
    #expect(HearthMetrics.groupInset == 16)
    #expect(HearthMetrics.rowMinHeight == 62)
    #expect(HearthMetrics.rowSidePadding == 16)
    #expect(HearthMetrics.iconTile == 36)
    #expect(HearthMetrics.iconTileRadius == 12)
    #expect(HearthMetrics.dividerInset == 66)
    #expect(HearthMetrics.switchW == 46)
    #expect(HearthMetrics.switchH == 28)
    #expect(HearthMetrics.switchThumb == 20)
    #expect(HearthMetrics.buttonH == 40)
    #expect(HearthMetrics.buttonHSmall == 32)
    #expect(HearthMetrics.chipH == 30)
    #expect(HearthMetrics.miniCardW == 174)
    #expect(HearthMetrics.miniCardRadius == 22)
}
