import Foundation
import Testing
@testable import HearthKit

/// Front door + garage must both fit a medium Alarm widget above the arm button.
@Suite("Alarm door rows layout")
struct AlarmDoorRowsLayoutTests {
    private typealias Metrics = AlarmDoorRowsMetrics
    /// The header is the taller of the 26pt reload button and the two-line "Checked" stamp
    /// (caption, 11pt, lines overlapped by 1pt) at the card's text size.
    private static let reloadButton = 26.0
    private static let stampSize = 11.0
    private static let stampOverlap = 1.0

    private static func available(card: Double, textScale: Double) -> Double {
        let stamp = 2 * stampSize * textScale * Metrics.lineHeightFactor - stampOverlap
        return card - AlarmCardMetrics.surfaceTopPadding - AlarmCardMetrics.surfaceBottomPadding
            - max(reloadButton, stamp) - AlarmCardMetrics.actionHeight
    }

    private static func fits(_ layout: AlarmDoorRowsLayout, in available: Double) -> Bool {
        layout.contentHeight + 2 * Metrics.margin <= available + 0.001
            && layout.textHeight + 2 * Metrics.rowVerticalPadding <= layout.rowHeight + 0.001
            && layout.buttonHeight + 2 * Metrics.buttonInset <= layout.rowHeight + 0.001
    }

    @Test("Two compact rows only when a garage row is shown")
    func compactDecision() {
        var snapshot = AlarmSnapshot.sample
        #expect(!snapshot.compactDoorRows)
        snapshot.garage = AlarmGarageRow(entityID: "cover.garage", name: "Garage", state: "Closed")
        #expect(snapshot.compactDoorRows)
        snapshot.setup = true
        #expect(!snapshot.compactDoorRows)
    }

    @Test("329×155 at Normal: both rows fit at full text size")
    func smallNormal() {
        let available = Self.available(card: 155, textScale: 1)
        #expect(available == 78)
        let layout = alarmDoorRowsLayout(availableHeight: available, textScale: 1)
        #expect(Self.fits(layout, in: available))
        #expect(layout.rowHeight == 32)
        #expect(layout.textScale == 1)
        #expect(layout.nameSize == 13)
        #expect(layout.statusSize == 11)
        #expect(layout.buttonHeight == 26)
    }

    @Test("329×155 at Larger: both rows fit, the row text gives up a little size")
    func smallLarger() {
        let available = Self.available(card: 155, textScale: 1.12)
        let layout = alarmDoorRowsLayout(availableHeight: available, textScale: 1.12)
        #expect(Self.fits(layout, in: available))
        #expect(layout.textScale < 1.12)
        #expect(layout.textScale > 0.93)
        #expect(layout.statusSize >= 10.3)
    }

    @Test("364×170: both rows fit at the chosen text size", arguments: [1.0, 1.12])
    func large(textScale: Double) {
        let available = Self.available(card: 170, textScale: textScale)
        let layout = alarmDoorRowsLayout(availableHeight: available, textScale: textScale)
        #expect(Self.fits(layout, in: available))
        #expect(layout.textScale == textScale)
        #expect(layout.rowHeight == Metrics.maximumRowHeight)
        #expect(layout.nameSize == Metrics.nameSize * textScale)
    }

    @Test("Smaller text is honoured, never enlarged to fill the row")
    func smallerText() {
        let layout = alarmDoorRowsLayout(availableHeight: Self.available(card: 155, textScale: 0.9), textScale: 0.9)
        #expect(layout.textScale == 0.9)
    }

    @Test("Rows never outgrow the space or the row cap", arguments: [0.0, 20, 48, 60, 78, 93, 140, 300])
    func rowsStayInside(available: Double) {
        let layout = alarmDoorRowsLayout(availableHeight: available, textScale: 1.12)
        #expect(layout.rowHeight >= 0)
        #expect(layout.rowHeight <= Metrics.maximumRowHeight)
        #expect(layout.contentHeight + 2 * Metrics.margin <= max(available, 2 * Metrics.margin + Metrics.rowSpacing) + 0.001)
        #expect(layout.buttonHeight >= 0)
        #expect(layout.buttonHeight <= Metrics.maximumButtonHeight)
        #expect(layout.textScale >= Metrics.minimumTextScale)
    }
}
