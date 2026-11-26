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
    public static func load() -> [GlanceFeed] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        // Corrupt/unreadable JSON → treat as empty (never crash)
        guard let feeds = try? glanceFeedsFromJson(data) else {
            return []
        }

        return feeds
    }

    // MARK: - Private Helpers

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
