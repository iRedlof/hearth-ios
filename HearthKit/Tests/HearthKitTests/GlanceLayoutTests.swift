import Testing
import Foundation
@testable import HearthKit

@Suite("GlanceLayout")
struct GlanceLayoutTests {

    @Test("2x2 layout shows more content than 2x1")
    func largeLayoutShowsMoreContent() {
        let summary = GlanceSummary(
            verdict: .needYou,
            word: "2 need you",
            tone: .warn,
            lines: ["Garage open 41 min", "Upstairs primary open"],
            support: "Checked 9:41",
            calmLine: nil
        )

        let small = glanceLayout(summary: summary, size: .small2x1)
        let large = glanceLayout(summary: summary, size: .small2x2)

        #expect(small.compact)
        #expect(!large.compact)

        // 2x2 should show more lines and support
        #expect(large.showsLines >= small.showsLines)
        #expect(large.showsSupport || !small.showsSupport)
    }

    @Test("Minimal content fits in 2x1")
    func minimalContentFits2x1() {
        let summary = GlanceSummary(
            verdict: .ok,
            word: "OK",
            tone: .ok,
            lines: [],
            support: "Checked 9:41",
            calmLine: "Alarm · Doors · Lights"
        )

        let plan = glanceLayout(summary: summary, size: .small2x1)

        #expect(plan.compact)
        #expect(plan.word == "OK")
        #expect(plan.showsLines == 0) // No items to show
    }

    @Test("Word is never truncated")
    func wordNeverTruncated() {
        let longWord = "12 need you"
        let summary = GlanceSummary(
            verdict: .needYou,
            word: longWord,
            tone: .warn,
            lines: ["Item 1", "Item 2"],
            support: "Checked 9:41",
            calmLine: nil
        )

        let plan = glanceLayout(summary: summary, size: .small2x1)

        // Word is always shown in full
        #expect(plan.word == longWord)
        #expect(plan.wordNeverShortened)
    }

    @Test("Support shown when honesty required (OK state)")
    func supportShownWhenHonestyRequired() {
        let summary = GlanceSummary(
            verdict: .ok,
            word: "OK",
            tone: .ok,
            lines: [],
            support: "Checked 9:41",
            calmLine: "Alarm · Doors"
        )

        let plan = glanceLayout(summary: summary, size: .small2x2)

        // Support should be shown for OK (honesty required)
        #expect(plan.showsSupport)
    }

    @Test("Key placement follows priority rules")
    func keyPlacementFollowsPriority() {
        let summary = GlanceSummary(
            verdict: .needYou,
            word: "1 needs you",
            tone: .warn,
            lines: ["Garage open"],
            support: "Checked 9:41",
            calmLine: nil,
            key: GlanceKey(label: "Check", action: .refresh)
        )

        let smallPlan = glanceLayout(summary: summary, size: .small2x1)
        let largePlan = glanceLayout(summary: summary, size: .small2x2)

        // 2x2 should show key (more room)
        #expect(largePlan.showsKey)
    }

    @Test("Calm line shown in 2x2 when OK")
    func calmLineShownIn2x2WhenOK() {
        let summary = GlanceSummary(
            verdict: .ok,
            word: "OK",
            tone: .ok,
            lines: [],
            support: "Checked 9:41",
            calmLine: "Alarm · Doors · Lights"
        )

        let plan = glanceLayout(summary: summary, size: .small2x2)

        #expect(plan.showsCalmLine)
        #expect(plan.showsSupport) // OK needs support (honesty)
    }

    @Test("Multiple items prioritized correctly")
    func multipleItemsPrioritized() {
        let summary = GlanceSummary(
            verdict: .needYou,
            word: "3 need you",
            tone: .warn,
            lines: ["Item 1", "Item 2", "Item 3"],
            support: "Checked 9:41",
            calmLine: nil
        )

        let plan = glanceLayout(summary: summary, size: .small2x2)

        // Should show up to 2 lines max
        #expect(plan.showsLines <= 2)
        #expect(plan.showsLines > 0)
    }
}
