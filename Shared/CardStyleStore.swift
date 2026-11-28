import Foundation
import HearthKit
import WidgetKit
import os.log

/// The "All cards" style and each widget kind's own, kept in the App Group so the app and the
/// widgets read the same values. Android keys a card's own style by placed widget; WidgetKit's
/// static widgets have no per-placement identity, so iOS keys it by kind.
public enum CardStyleStore {
    private static let appGroup = "group.com.rohit.hearth"
    private static let globalKey = "cardStyleGlobal"
    private static let overridesKey = "cardStyleOverrides"
    private static let logger = Logger(subsystem: "com.rohit.hearth", category: "CardStyle")

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// The style a widget of `kind` draws with: its own if it has one, else All cards'.
    public static func effectiveStyle(for kind: HomeWidgetKind?) -> CardStyle {
        guard let kind else { return global() }
        return resolveStyle(global: global(), override: override(for: kind))
    }

    /// The "All cards" style; `.default` until one is chosen.
    public static func global() -> CardStyle {
        guard let data = defaults.data(forKey: globalKey) else { return .default }
        do {
            return try JSONDecoder().decode(CardStyle.self, from: data)
        } catch {
            logger.error("All-cards style unreadable, using the default: \(error.localizedDescription, privacy: .public)")
            return .default
        }
    }

    /// A widget kind's own style; nil: it follows All cards.
    public static func override(for kind: HomeWidgetKind) -> CardStyle? {
        loadOverrides()[kind.rawValue]
    }

    /// Saves `style` where the page is editing, then redraws the widgets.
    public static func save(_ style: CardStyle, to target: CardStyleSaveTarget) throws {
        switch target {
        case .allCards:
            defaults.set(try JSONEncoder().encode(style), forKey: globalKey)
        case .own(let kind):
            try saveOverrides(loadOverrides().merging([kind.rawValue: style]) { _, new in new })
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The widget kind follows All cards again.
    public static func clearOverride(for kind: HomeWidgetKind) throws {
        try saveOverrides(loadOverrides().filter { $0.key != kind.rawValue })
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Private Helpers

    private static func loadOverrides() -> [String: CardStyle] {
        guard let data = defaults.data(forKey: overridesKey) else { return [:] }
        do {
            return try cardStyleOverrides(fromStored: data)
        } catch {
            logger.error("Own card styles unreadable, following All cards: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private static func saveOverrides(_ overrides: [String: CardStyle]) throws {
        defaults.set(try JSONEncoder().encode(overrides), forKey: overridesKey)
    }
}
