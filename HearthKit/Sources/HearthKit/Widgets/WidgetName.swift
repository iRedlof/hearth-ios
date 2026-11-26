import Foundation

/// Resolves the display name for a widget: uses the custom name if non-empty, otherwise the kind default.
/// Trims whitespace from custom names.
public func widgetDisplayName(custom: String?, kindDefault: String) -> String {
    let trimmed = custom?.trimmingCharacters(in: .whitespaces) ?? ""
    return trimmed.isEmpty ? kindDefault : trimmed
}
