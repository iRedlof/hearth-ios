import Testing
import Foundation
@testable import HearthKit

@Suite("Action History Store Tests")
struct ActionHistoryStoreTests {
    private let testSuiteName = "test.hearth.routines.actionhistorystore"

    // MARK: - Test: Load returns empty for absent key

    @Test("Load returns empty array when key is absent")
    func testLoadReturnsEmptyForAbsentKey() {
        // Use a unique suite name to avoid cross-test contamination
        let uniqueSuite = testSuiteName + ".absent"
        let defaults = UserDefaults(suiteName: uniqueSuite)!
        defaults.removePersistentDomain(forName: uniqueSuite)

        let history = ActionHistoryStore.load(defaults: defaults)
        #expect(history.isEmpty)

        defaults.removePersistentDomain(forName: uniqueSuite)
    }

    // MARK: - Test: Save and load round-trip

    @Test("Save and load round-trip preserves data")
    func testSaveAndLoad() {
        // Use a unique suite name to avoid cross-test contamination
        let uniqueSuite = testSuiteName + ".saveload"
        let defaults = UserDefaults(suiteName: uniqueSuite)!
        defaults.removePersistentDomain(forName: uniqueSuite)

        let entry = ActionHistoryRecord(timestamp: Date(), entityIDs: ["lock.a", "alarm.b"])
        ActionHistoryStore.save([entry], defaults: defaults)

        let loaded = ActionHistoryStore.load(defaults: defaults)
        #expect(loaded.count == 1)
        #expect(loaded.first?.entityIDs == ["lock.a", "alarm.b"])
        #expect(loaded.first?.id == entry.id)

        defaults.removePersistentDomain(forName: uniqueSuite)
    }

    // MARK: - Test: Load handles corrupt data

    @Test("Load returns empty array for corrupt JSON data")
    func testLoadHandlesCorruptData() {
        // Use a unique suite name to avoid cross-test contamination
        let uniqueSuite = testSuiteName + ".corrupt"
        let defaults = UserDefaults(suiteName: uniqueSuite)!
        defaults.removePersistentDomain(forName: uniqueSuite)

        // Write genuinely corrupt bytes to the key
        defaults.set(Data([0xFF, 0xFF, 0x00, 0xAB]), forKey: "routines.history")

        let history = ActionHistoryStore.load(defaults: defaults)
        #expect(history.isEmpty)  // Corrupt → default to empty

        defaults.removePersistentDomain(forName: uniqueSuite)
    }

    // MARK: - Test: Record appends and prunes

    @Test("Record appends new entry and prunes old entries")
    func testRecordAppendsAndPrunes() {
        // Use a unique suite name to avoid cross-test contamination
        let uniqueSuite = testSuiteName + ".prune"
        let defaults = UserDefaults(suiteName: uniqueSuite)!
        defaults.removePersistentDomain(forName: uniqueSuite)

        let now = Date()

        // Record an old entry (older than 28-day retention)
        let oldEntry = ActionHistoryRecord(timestamp: now.addingTimeInterval(-29 * 86400), entityIDs: ["old.lock"])
        ActionHistoryStore.record(oldEntry, now: now, defaults: defaults)

        // Record a recent entry
        let recentEntry = ActionHistoryRecord(timestamp: now.addingTimeInterval(-1 * 86400), entityIDs: ["recent.lock"])
        ActionHistoryStore.record(recentEntry, now: now, defaults: defaults)

        // Load and verify: old entry should be pruned, only recent remains
        let loaded = ActionHistoryStore.load(defaults: defaults)
        #expect(loaded.count == 1)
        #expect(loaded.first?.entityIDs == ["recent.lock"])

        defaults.removePersistentDomain(forName: uniqueSuite)
    }

    // MARK: - Test: Record appends to existing history

    @Test("Record appends to existing history")
    func testRecordAppendsToExisting() {
        // Use a unique suite name to avoid cross-test contamination
        let uniqueSuite = testSuiteName + ".append"
        let defaults = UserDefaults(suiteName: uniqueSuite)!
        defaults.removePersistentDomain(forName: uniqueSuite)

        let now = Date()

        // Record first entry
        let entry1 = ActionHistoryRecord(timestamp: now.addingTimeInterval(-2 * 86400), entityIDs: ["lock.a"])
        ActionHistoryStore.record(entry1, now: now, defaults: defaults)

        // Record second entry
        let entry2 = ActionHistoryRecord(timestamp: now.addingTimeInterval(-1 * 86400), entityIDs: ["lock.b"])
        ActionHistoryStore.record(entry2, now: now, defaults: defaults)

        // Load and verify both are present
        let loaded = ActionHistoryStore.load(defaults: defaults)
        #expect(loaded.count == 2)
        #expect(loaded.contains(where: { $0.entityIDs == ["lock.a"] }))
        #expect(loaded.contains(where: { $0.entityIDs == ["lock.b"] }))

        defaults.removePersistentDomain(forName: uniqueSuite)
    }
}
