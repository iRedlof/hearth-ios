import Testing
import Foundation
@testable import HearthKit

@Suite("GlanceSummary Tests")
struct GlanceSummaryTests {

    // MARK: - Test Fixtures

    private let now = Date(timeIntervalSince1970: 1700000000) // 2023-11-14 22:13:20 UTC
    private let fresh = Date(timeIntervalSince1970: 1700000000 - 10 * 60) // 10 min ago

    // MARK: - Empty State

    @Test("Empty feeds returns Set up verdict")
    func emptyFeedsReturnsSetUp() {
        let summary = glanceSummary([], now: now)

        #expect(summary.verdict == .empty)
        #expect(summary.word == "Set up")
        #expect(summary.tone == .neutral)
        #expect(summary.lines.isEmpty)
        #expect(summary.calmLine == nil)
    }

    // MARK: - OK State

    @Test("All calm and fresh returns OK verdict")
    func allCalmAndFreshReturnsOK() {
        let feeds = [
            GlanceFeed(kind: .alarm, checkedAt: fresh, error: false, items: [], calm: true),
            GlanceFeed(kind: .doors, checkedAt: fresh, error: false, items: [], calm: true)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .ok)
        #expect(summary.word == "OK")
        #expect(summary.tone == .ok)
        #expect(summary.lines.isEmpty)
        #expect(summary.calmLine == "Alarm · Doors") // iOS uses displayName when calm
    }

    @Test("OK verdict includes support with checked time")
    func okVerdictIncludesSupportWithCheckedTime() {
        let feeds = [
            GlanceFeed(kind: .alarm, checkedAt: fresh, error: false, items: [], calm: true)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .ok)
        #expect(summary.support.starts(with: "Checked "))
    }

    // MARK: - Need You State

    @Test("One act item returns needYou with singular word")
    func oneActItemReturnsNeedYouSingular() {
        let item = GlanceItem(text: "Garage open", severity: .act)
        let feeds = [
            GlanceFeed(kind: .doors, checkedAt: fresh, error: false, items: [item], calm: false)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .needYou)
        #expect(summary.word == "1 needs you")
        #expect(summary.tone == .warn)
        #expect(summary.lines == ["Garage open"])
    }

    @Test("Multiple items return needYou with plural word")
    func multipleItemsReturnNeedYouPlural() {
        let items = [
            GlanceItem(text: "Garage open", severity: .act),
            GlanceItem(text: "Front door unlocked", severity: .alert)
        ]
        let feeds = [
            GlanceFeed(kind: .doors, checkedAt: fresh, error: false, items: items, calm: false)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .needYou)
        #expect(summary.word == "2 need you")
        #expect(summary.lines.count == 2)
    }

    // MARK: - Alarm State

    @Test("Alarm severity item returns alarm verdict")
    func alarmSeverityReturnsAlarmVerdict() {
        let item = GlanceItem(text: "Break-in detected", severity: .alarm)
        let feeds = [
            GlanceFeed(kind: .alarm, checkedAt: fresh, error: false, items: [item], calm: false)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .alarm)
        #expect(summary.word == "Alarm!")
        #expect(summary.tone == .warn) // iOS uses warn for alarm (no red tone)
        #expect(summary.lines == ["Break-in detected"])
    }

    // MARK: - Can't Check State (Critical: Never False OK)

    @Test("Error feed returns cantCheck even with calm feeds")
    func errorFeedReturnsCantCheckNeverFalseOK() {
        let feeds = [
            GlanceFeed(kind: .alarm, checkedAt: fresh, error: false, items: [], calm: true),
            GlanceFeed(kind: .doors, checkedAt: fresh, error: true, items: [], calm: false) // ERROR
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .cantCheck) // NEVER return .ok when any feed has error
        #expect(summary.word == "Can't check")
        #expect(summary.tone == .neutral)
    }

    @Test("Stale feed returns cantCheck with last known support")
    func staleFeedReturnsCantCheckWithLastKnown() {
        let staleTime = Date(timeIntervalSince1970: 1700000000 - 30 * 60) // 30 min ago (stale)
        let feeds = [
            GlanceFeed(kind: .alarm, checkedAt: staleTime, error: false, items: [], calm: true)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .cantCheck)
        #expect(summary.word == "Can't check")
        #expect(summary.support.contains("Checked ")) // Shows last check time
    }

    @Test("Stale feed with calm cannot claim OK")
    func staleFeedWithCalmCannotClaimOK() {
        let staleTime = Date(timeIntervalSince1970: 1700000000 - 30 * 60)
        let feeds = [
            GlanceFeed(kind: .alarm, checkedAt: staleTime, error: false, items: [], calm: true),
            GlanceFeed(kind: .doors, checkedAt: fresh, error: false, items: [], calm: true)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.verdict == .cantCheck) // NOT .ok, because one feed is stale
    }

    // MARK: - Severity Ordering

    @Test("Items are ranked by severity descending")
    func itemsRankedBySeverityDescending() {
        let items = [
            GlanceItem(text: "Warning", severity: .warn),
            GlanceItem(text: "Urgent", severity: .alert),
            GlanceItem(text: "Action needed", severity: .act)
        ]
        let feeds = [
            GlanceFeed(kind: .doors, checkedAt: fresh, error: false, items: items, calm: false)
        ]

        let summary = glanceSummary(feeds, now: now)

        // Alert (highest) should be first
        #expect(summary.lines.first == "Urgent")
        #expect(summary.lines == ["Urgent", "Action needed", "Warning"])
    }

    @Test("Calm severity items are excluded from lines")
    func calmSeverityExcludedFromLines() {
        let items = [
            GlanceItem(text: "All good", severity: .calm),
            GlanceItem(text: "Warning", severity: .warn)
        ]
        let feeds = [
            GlanceFeed(kind: .alarm, checkedAt: fresh, error: false, items: items, calm: false)
        ]

        let summary = glanceSummary(feeds, now: now)

        #expect(summary.lines == ["Warning"]) // Calm items not included
    }
}
