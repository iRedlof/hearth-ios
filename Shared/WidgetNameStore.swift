import Foundation
import HearthKit

/// Per-widget display name store using App Group shared defaults.
/// Keys are prefixed with "widget.name." followed by the widget kind rawValue.
enum WidgetNameStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let keyPrefix = "widget.name."

    private static func key(for kind: HomeWidgetKind) -> String {
        keyPrefix + kind.rawValue
    }

    /// Gets the custom display name for a widget kind, or nil if using the default.
    static func name(for kind: HomeWidgetKind) -> String? {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return nil }
        return defaults.string(forKey: key(for: kind))
    }

    /// Sets the custom display name for a widget kind. Pass nil to reset to the default.
    static func setName(_ name: String?, for kind: HomeWidgetKind) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(name, forKey: key(for: kind))
    }
}
