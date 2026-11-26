import Foundation

/// Small keeps one reading and a single entry-bound navigation action.
public struct ThermostatSmallContent: Equatable, Sendable {
    public let focused: ThermostatFocusedContent
    public let status: String?
    public let mode: String
    public let target: String?
    public let placeholder: String
    public let statusSymbol: String
    public let destination: ThermostatDestination
    public var navigationURL: URL? { thermostatReadingsURL(for: destination) }
}

public func thermostatSmallContent(_ presentation: ThermostatPresentation,
                                   destination: ThermostatDestination = .inert) -> ThermostatSmallContent {
    let focused = thermostatFocusedContent(presentation, accessibility: false, destination: destination)
    let historical = focused.roomAttribution == "Last known"
    let placeholder: String
    switch presentation.recovery {
    case .setup: placeholder = "Set up"
    case .authentication: placeholder = "Sign in"
    case .sharedStoreUnavailable: placeholder = "Unavailable"
    default: placeholder = focused.room.availability == .unavailable ? "Unavailable" : "No reading"
    }
    let status: String?
    if historical {
        status = focused.recoveryTitle.map { "Last known · \($0)" } ?? "Last known"
    } else if focused.room.value == nil, focused.recoveryTitle == placeholder {
        status = nil
    } else { status = focused.recoveryTitle }
    let settled: Bool
    switch presentation.operation {
    case .none: settled = true
    case .pending, .failed: settled = false
    }
    let mode: String
    if !historical, presentation.recovery == .none, settled,
       let action = presentation.state?.action {
        mode = action.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    } else { mode = focused.mode }
    let target = focused.context == nil && focused.room.value != nil && !historical
        && presentation.recovery == .none && settled ? focused.target : nil
    let symbol: String
    if presentation.recovery != .none { symbol = "exclamationmark.circle" }
    else {
        switch presentation.operation {
        case .pending: symbol = "arrow.triangle.2.circlepath"
        case .failed: symbol = "exclamationmark.circle"
        case .none: symbol = historical ? "clock" : "thermometer.medium"
        }
    }
    return ThermostatSmallContent(focused: focused, status: status, mode: mode,
        target: target, placeholder: placeholder, statusSymbol: symbol, destination: destination)
}

public func thermostatSmallAccessibility(_ content: ThermostatSmallContent,
                                        locale: Locale = .current) -> String {
    let name = content.focused.room.name
    let navigation = content.destination == .inert
        ? "Example \(name). Open readings and controls inactive."
        : "Open \(name) readings and controls."
    var parts = [navigation, thermostatFocusedReadingAccessibility(content.focused.room,
        attribution: content.focused.roomAttribution, locale: locale)]
    if let status = content.status ?? content.focused.recoveryTitle { parts.append(status) }
    parts.append(content.mode)
    if let context = content.focused.context {
        parts.append(thermostatFocusedReadingAccessibility(context, locale: locale))
        if context.failure != nil { parts.append("Context check failed") }
    }
    return parts.joined(separator: ". ")
}
