import Foundation

/// App Group persistence for Glance feeds. Each widget writes its last reading,
/// and the Glance widget reads all of them to determine the overall state.
public enum GlanceFeedStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let key = "glanceFeeds"

    /// Save a feed (merge by kind: replaces any existing feed with the same kind).
    public static func save(_ feed: GlanceFeed) {
        var feeds = load()

        // Remove any existing feed with the same kind
        feeds.removeAll { $0.kind == feed.kind }

        // Add the new feed
        feeds.append(feed)

        // Persist
        guard let data = try? glanceFeedsToJson(feeds) else { return }
        defaults.set(data, forKey: key)
    }

    /// Load all feeds from the App Group.
    ///
    /// Distinguishes a genuinely absent key (no widgets have written yet → `[]`, correct "not
    /// configured" signal) from present-but-undecodable data (corruption). Corrupt data returns a
    /// single sentinel error feed so `glanceSummary` yields `.cantCheck` — never a false `.empty`
    /// "Set up" for a user who has already placed widgets.
    public static func load() -> [GlanceFeed] {
        guard let data = defaults.data(forKey: key) else {
            return []  // Absent key: genuinely empty.
        }

        // Present-but-undecodable JSON → surface as an honest error feed (never crash, never
        // masquerade as "not set up").
        guard let feeds = try? glanceFeedsFromJson(data) else {
            return [corruptSentinelFeed]
        }

        return feeds
    }

    /// Sentinel feed emitted when stored data cannot be decoded. Carries `error: true` with no
    /// items so the summary resolves to `.cantCheck`.
    static let corruptSentinelFeed = GlanceFeed(
        kind: .glance,
        checkedAt: nil,
        error: true,
        items: [],
        calm: false
    )

    // MARK: - Private Helpers

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
