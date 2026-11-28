import Testing
@testable import HearthKit

@Suite("Two-panel widgets: what gives way when room is short")
struct PanelFitTests {
    @Test("Tiles: all four as pictured, then all four shorter, then one row")
    func tiles() {
        let choices = PanelTileFit.choices
        #expect(choices.first == PanelTileFit(rows: 2, roomy: true))
        #expect(choices.map(\.tileLimit) == [4, 4, 2, 2])
        #expect(choices.map(\.roomy) == [true, false, true, false])
        #expect(choices.last?.rows == 1)
        #expect(choices.allSatisfy { $0.tileLimit <= PanelLimits.maxTiles })
    }

    @Test("Rows: three, then two, then one; never none")
    func rows() {
        #expect(PanelRowFit.choices == [3, 2, 1])
    }

    @Test("The rail's glyph and answer shrink before a line of detail is dropped")
    func rail() {
        let choices = PanelRailFit.choices
        let firstDrop = choices.firstIndex { $0.detailLines < 3 }
        let firstShrink = choices.firstIndex { $0.wordSize < 25 }
        #expect(firstShrink.map { $0 < (firstDrop ?? 0) } == true)
        for (earlier, later) in zip(choices, choices.dropFirst()) {
            #expect(later.iconSize <= earlier.iconSize)
            #expect(later.wordSize <= earlier.wordSize)
            #expect(later.longWordSize <= earlier.longWordSize)
            #expect(later.detailLines <= earlier.detailLines)
            #expect(later != earlier)
        }
        #expect(choices.allSatisfy { $0.longWordSize < $0.wordSize })
        #expect(choices.last?.detailLines == 0)
        // Every size is tried with all three lines of detail before a line is given up.
        let smallest = choices.map(\.wordSize).min()
        #expect(choices.first { $0.detailLines < 3 }?.wordSize == smallest)
    }

    @Test("Tiles are laid out in rows of two; an odd one sits alone")
    func chunks() {
        #expect(panelRows([1, 2, 3, 4], columns: 2) == [[1, 2], [3, 4]])
        #expect(panelRows([1, 2, 3], columns: 2) == [[1, 2], [3]])
        #expect(panelRows([Int](), columns: 2).isEmpty)
        #expect(panelRows([1, 2], columns: 0).isEmpty)
    }
}
