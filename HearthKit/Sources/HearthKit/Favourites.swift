import Foundation

/// A favourite entity (switch / light / fan / input_boolean / script): its name and whether it's on.
public struct Fav: Sendable, Equatable {
    public let id: String; public let name: String; public let on: Bool
    public init(id: String, name: String, on: Bool) { self.id = id; self.name = name; self.on = on }
    public var domain: String { String(id.prefix { $0 != "." }) }
}

/// The service to toggle a favourite: scripts always run; everything else flips to the opposite of
/// its current state. Ported from Android `favServiceFor`.
public func favServiceFor(_ id: String, on: Bool) -> (domain: String, service: String) {
    let domain = String(id.prefix { $0 != "." })
    if domain == "script" { return ("script", "turn_on") }
    return (domain, on ? "turn_off" : "turn_on")
}
