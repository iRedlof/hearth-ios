import Foundation

/// Formats the Home Assistant hero detail string for the connection status display.
/// - Parameters:
///   - host: The Home Assistant host URL (may be empty)
///   - deviceCount: Optional count of discovered devices
///   - widgetCount: Optional count of widgets configured
/// - Returns: A formatted detail string ("Not connected", bare host, or "N devices · M widgets")
public func haHeroDetail(host: String, deviceCount: Int?, widgetCount: Int?) -> String {
    let trimmed = host.trimmingCharacters(in: .whitespaces)

    // If no host, show "Not connected"
    if trimmed.isEmpty {
        return "Not connected"
    }

    // If we have counts, show them
    if let devices = deviceCount, let widgets = widgetCount {
        let deviceText = devices == 1 ? "device" : "devices"
        let widgetText = widgets == 1 ? "widget" : "widgets"
        return "\(devices) \(deviceText) · \(widgets) \(widgetText)"
    }

    // Otherwise, show just the host
    return trimmed
}
