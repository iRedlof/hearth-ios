import Foundation

/// Whose style the Card style page edits, and how its rows describe that.

/// Which scope the page edits the moment it opens: the shared "all cards" style ONLY on the
/// All-cards page (`kind` nil). A widget opens on "Just this card", so changing one widget's look
/// never restyles the rest (`cardStyleFollowsAll` in `CardStyles.kt`).
public func cardStyleFollowsAll(forKind kind: HomeWidgetKind?) -> Bool {
    kind == nil
}

/// Where a change on the page is saved.
public enum CardStyleSaveTarget: Sendable, Equatable {
    case allCards
    case own(HomeWidgetKind)
}

public func cardStyleSaveTarget(kind: HomeWidgetKind?, follows: Bool) -> CardStyleSaveTarget {
    guard let kind, !follows else { return .allCards }
    return .own(kind)
}

/// Each widget's own style as stored, keyed by `HomeWidgetKind` raw value. A key that is no longer
/// a widget kind (Glance and Doors were removed) is dropped, so the other cards keep their styles and the next
/// save forgets it.
public func cardStyleOverrides(fromStored data: Data) throws -> [String: CardStyle] {
    try JSONDecoder().decode([String: CardStyle].self, from: data)
        .filter { HomeWidgetKind(rawValue: $0.key) != nil }
}

/// The per-widget "Card style" row's subtitle (`SettingsList.kt:277-279`).
public func cardStyleEntrySubtitle(own: CardStyle?) -> String {
    own.map { "Its own: \($0.summary)" } ?? "Follows All cards"
}

/// The text under "This card uses" (`CardStylePage.kt:151-154`).
public func cardStyleScopeHelper(follows: Bool, name: String) -> String {
    follows
        ? "Changes below restyle all your cards. Pick \"Just this card\" to style \(name) on its own."
        : "Changes below restyle only \(name)."
}

/// The text under "Background" (`CardStylePage.kt:163`). Android's has nothing about Glass to drop.
public let cardStyleBackgroundHelper = "Alarm, Thermostat, Car and ChargePoint use Beacon compartments. "
    + "Status gives a dark body; Snow gives a light body. ChargePoint keeps its orange rail; "
    + "the others follow the widget’s state."

/// The All-cards preview's ‹ › stepper: wraps around the added widgets, and stays in range when
/// their number changes.
public func cardStylePreviewIndex(_ current: Int, step: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let clamped = min(max(current, 0), count - 1)
    return ((clamped + step) % count + count) % count
}
