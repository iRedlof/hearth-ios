import Testing
import Foundation
@testable import HearthKit

@Suite("GlanceFeedStore", .serialized)
struct GlanceFeedStoreTests {

    @Test("Feed round-trips through JSON")
    func feedRoundTripsJSON() throws {
        let now = Date()
        let feeds = [
            GlanceFeed(
                kind: .alarm,
                checkedAt: now,
                error: false,
                items: [
                    GlanceItem(text: "Armed away", severity: .calm)
                ],
                calm: true
            ),
            GlanceFeed(
                kind: .doors,
                checkedAt: now.addingTimeInterval(-60),
                error: false,
                items: [
                    GlanceItem(text: "Garage open 41 min", severity: .warn)
                ],
                calm: false
            )
        ]

        let json = try glanceFeedsToJson(feeds)
        let decoded = try glanceFeedsFromJson(json)

        #expect(decoded.count == 2)
        #expect(decoded[0].kind == .alarm)
        #expect(decoded[0].calm)
        #expect(decoded[0].items.count == 1)
        #expect(decoded[0].items[0].text == "Armed away")
        #expect(decoded[0].items[0].severity == .calm)

        #expect(decoded[1].kind == .doors)
        #expect(!decoded[1].calm)
        #expect(decoded[1].items.count == 1)
        #expect(decoded[1].items[0].text == "Garage open 41 min")
        #expect(decoded[1].items[0].severity == .warn)
    }

    @Test("Saving same kind twice keeps latest")
    func savingSameKindKeepsLatest() {
        // Clear at start to avoid state leakage
        let defaults = UserDefaults(suiteName: "group.com.rohit.hearth")
        defaults?.removeObject(forKey: "glanceFeeds")

        let now = Date()

        // Save first feed for alarm
        let feed1 = GlanceFeed(
            kind: .alarm,
            checkedAt: now,
            error: false,
            items: [GlanceItem(text: "Armed away", severity: .calm)],
            calm: true
        )
        GlanceFeedStore.save(feed1)

        // Save second feed for alarm (should replace)
        let feed2 = GlanceFeed(
            kind: .alarm,
            checkedAt: now.addingTimeInterval(60),
            error: false,
            items: [GlanceItem(text: "Disarmed", severity: .warn)],
            calm: false
        )
        GlanceFeedStore.save(feed2)

        // Load and verify only one alarm feed exists (the latest)
        let loaded = GlanceFeedStore.load()
        let alarmFeeds = loaded.filter { $0.kind == .alarm }

        #expect(alarmFeeds.count == 1)
        #expect(alarmFeeds[0].items[0].text == "Disarmed")
        #expect(!alarmFeeds[0].calm)

        // Clean up
        defaults?.removeObject(forKey: "glanceFeeds")
    }

    @Test("Different kinds are stored separately")
    func differentKindsStoredSeparately() {
        // Clear at start to avoid state leakage
        let defaults = UserDefaults(suiteName: "group.com.rohit.hearth")
        defaults?.removeObject(forKey: "glanceFeeds")

        let now = Date()

        // Save feeds for different kinds
        GlanceFeedStore.save(GlanceFeed(
            kind: .alarm,
            checkedAt: now,
            error: false,
            items: [GlanceItem(text: "Armed", severity: .calm)],
            calm: true
        ))

        GlanceFeedStore.save(GlanceFeed(
            kind: .doors,
            checkedAt: now,
            error: false,
            items: [GlanceItem(text: "Closed", severity: .calm)],
            calm: true
        ))

        // Load and verify both exist
        let loaded = GlanceFeedStore.load()

        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.kind == .alarm })
        #expect(loaded.contains { $0.kind == .doors })

        // Clean up
        defaults?.removeObject(forKey: "glanceFeeds")
    }

    @Test("Corrupt JSON yields an error feed that reads as can't-check, not empty")
    func corruptJSONYieldsErrorFeed() throws {
        // Clear at start to avoid state leakage
        let defaults = UserDefaults(suiteName: "group.com.rohit.hearth")
        defaults?.removeObject(forKey: "glanceFeeds")

        let corruptData = "not valid json".data(using: .utf8)!

        // Decoding itself still throws (returns nil via try?).
        let feeds = try? glanceFeedsFromJson(corruptData)
        #expect(feeds == nil)

        // Present-but-undecodable data must surface as an error feed, NOT an empty store —
        // the user has placed widgets, so "Set up" would be a lie.
        defaults?.set(corruptData, forKey: "glanceFeeds")
        let loaded = GlanceFeedStore.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.error == true)
        #expect(loaded.first?.items.isEmpty == true)

        // The summary of a corrupt store must be .cantCheck (never .empty / "Set up").
        let summary = glanceSummary(loaded, now: Date())
        #expect(summary.verdict == .cantCheck)
        #expect(summary.word == "Can't check")

        // Clean up
        defaults?.removeObject(forKey: "glanceFeeds")
    }

    @Test("Absent key returns a genuinely empty store")
    func absentKeyReturnsEmpty() {
        let defaults = UserDefaults(suiteName: "group.com.rohit.hearth")
        defaults?.removeObject(forKey: "glanceFeeds")

        let loaded = GlanceFeedStore.load()
        #expect(loaded.isEmpty)
        #expect(glanceSummary(loaded, now: Date()).verdict == .empty)
    }

    @Test("Empty store returns empty array")
    func emptyStoreReturnsEmpty() {
        // Clear at start to avoid state leakage
        let defaults = UserDefaults(suiteName: "group.com.rohit.hearth")
        defaults?.removeObject(forKey: "glanceFeeds")

        let loaded = GlanceFeedStore.load()
        #expect(loaded.isEmpty)
    }

    @Test("Feed with error flag persists correctly")
    func feedWithErrorPersists() {
        // Clear at start to avoid state leakage
        let defaults = UserDefaults(suiteName: "group.com.rohit.hearth")
        defaults?.removeObject(forKey: "glanceFeeds")

        let errorFeed = GlanceFeed(
            kind: .alarm,
            checkedAt: Date(),
            error: true,
            items: [],
            calm: false
        )

        GlanceFeedStore.save(errorFeed)
        let loaded = GlanceFeedStore.load()

        #expect(loaded.count == 1)
        #expect(loaded[0].error)
        #expect(loaded[0].items.isEmpty)

        // Clean up
        defaults?.removeObject(forKey: "glanceFeeds")
    }
}
