import Foundation

/// Publishes only an opaque ticket ID or a stateless persistence-failure explanation.
public func carReadingsURL(for destination: CarReadingsDestination) -> URL? {
    switch destination {
    case .ticket(let id):
        URL(string: "hearth://car-readings/\(id.uuidString)")
    case .storageUnavailable:
        URL(string: "hearth://car-readings/unavailable")
    case .inert:
        nil
    }
}

/// Ignores unrelated or malformed URLs without consuming or logging their contents.
public func carReadingsDestination(from url: URL) -> CarReadingsDestination? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "hearth",
          components.host == "car-readings",
          components.user == nil,
          components.password == nil,
          components.port == nil,
          components.query == nil,
          components.fragment == nil else { return nil }

    let path = components.percentEncodedPath
    // Compare the original URL spelling as well: structural parsing can hide an empty port.
    guard url.absoluteString == "hearth://car-readings\(path)",
          !path.contains("%"),
          path.hasPrefix("/") else { return nil }
    let identifier = String(path.dropFirst())
    guard !identifier.isEmpty, !identifier.contains("/") else { return nil }
    if identifier == "unavailable" { return .storageUnavailable }
    guard let id = UUID(uuidString: identifier) else { return nil }
    return .ticket(id)
}
