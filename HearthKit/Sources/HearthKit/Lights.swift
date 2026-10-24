import Foundation

/// The lights (a `light.*` entity): on/off, brightness %, since when, and colour. Ported from Android
/// `LightsState.kt` (the Android grid-math is replaced by SwiftUI `LazyVGrid`).
public let LIGHTS_TEMPLATE = """
{%- set ns = namespace(out=[]) -%}
{%- for l in states.light -%}
  {%- set ns.out = ns.out + [{'entity_id': l.entity_id, 'state': l.state, 'name': l.name,
      'brightness': l.attributes.brightness | default(none), 'since': l.last_changed.isoformat(),
      'group': l.attributes.entity_id is defined, 'rgb': l.attributes.rgb_color | default(none)}] -%}
{%- endfor -%}
{{ ns.out | tojson }}
"""

public struct Light: Sendable, Equatable {
    public let id: String; public let name: String; public let on: Bool
    public let percent: Int?; public let since: Date?; public let rgb: UInt32?
    public init(id: String, name: String, on: Bool, percent: Int?, since: Date?, rgb: UInt32? = nil) {
        self.id = id; self.name = name; self.on = on; self.percent = percent; self.since = since; self.rgb = rgb
    }
}

public struct LightView: Sendable, Equatable {
    public let id: String; public let name: String; public let status: String; public let on: Bool
    public let percent: Int?; public let tile: String; public let rgb: UInt32?
    public init(id: String, name: String, status: String, on: Bool, percent: Int?, tile: String, rgb: UInt32?) {
        self.id = id; self.name = name; self.status = status; self.on = on; self.percent = percent; self.tile = tile; self.rgb = rgb
    }
}

public struct LightsSummary: Sendable, Equatable {
    public let headline: String; public let on: [LightView]; public let pinned: [LightView]
    public let onCount: Int; public let offCount: Int; public let off: [LightView]
    public init(headline: String, on: [LightView], pinned: [LightView], onCount: Int, offCount: Int, off: [LightView]) {
        self.headline = headline; self.on = on; self.pinned = pinned
        self.onCount = onCount; self.offCount = offCount; self.off = off
    }
}

public func lightView(_ l: Light, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> LightView {
    let since = sinceLabel(l.since, now: now, zone: zone, locale: locale)
    let status = l.on
        ? ["On", l.percent.map { "\($0)%" }, since].compactMap { $0 }.joined(separator: " · ")
        : ["Off", since].compactMap { $0 }.joined(separator: " · ")
    return LightView(id: l.id, name: l.name, status: status, on: l.on,
                     percent: l.on ? l.percent : nil, tile: l.on ? (since ?? "On") : "Off", rgb: l.rgb)
}

/// The card: headline, the on-lights (not pinned), the always-shown pinned set, counts, and the
/// hidden-off lights. Ported from Android `lightsSummary`.
public func lightsSummary(_ lights: [Light], now: Date, zone: TimeZone = .current, locale: Locale = .current,
                          pinned: Set<String> = []) -> LightsSummary {
    let on = lights.filter { $0.on }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    let always = lights.filter { pinned.contains($0.id) }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    let headline = on.isEmpty ? (lights.isEmpty ? "No lights found" : "All off")
        : (on.count == 1 ? "\(on[0].name) on" : "\(on.count) on")
    let offUnpinned = lights.filter { !$0.on && !pinned.contains($0.id) }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    return LightsSummary(
        headline: headline,
        on: on.filter { !pinned.contains($0.id) }.map { lightView($0, now: now, zone: zone, locale: locale) },
        pinned: always.map { lightView($0, now: now, zone: zone, locale: locale) },
        onCount: on.count,
        offCount: offUnpinned.count,
        off: offUnpinned.map { lightView($0, now: now, zone: zone, locale: locale) })
}

private let lightSegment = try! NSRegularExpression(pattern: "\\bsegment\\s*\\d+\\b", options: .caseInsensitive)
private func hasSegment(_ s: String) -> Bool {
    lightSegment.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

/// Parse `LIGHTS_TEMPLATE`'s reply: not groups, not LED segments, not offline.
public func lightsFromTemplate(_ json: String) -> [Light] {
    guard let data = json.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    return arr.compactMap { o in
        let state = (o["state"] as? String) ?? ""
        let id = (o["entity_id"] as? String) ?? ""
        let name = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        guard ["on", "off"].contains(state), !(o["group"] as? Bool ?? false), !id.isEmpty,
              !hasSegment(name), !hasSegment(id.replacingOccurrences(of: "_", with: " ")) else { return nil }
        let brightness = (o["brightness"] as? Double) ?? (o["brightness"] as? Int).map(Double.init)
        var rgb: UInt32?
        if let c = o["rgb"] as? [Any], c.count == 3 {
            let r = UInt32((c[0] as? Int) ?? 0), g = UInt32((c[1] as? Int) ?? 0), b = UInt32((c[2] as? Int) ?? 0)
            rgb = UInt32(0xFF00_0000) | (r << 16) | (g << 8) | b
        }
        return Light(id: id, name: name, on: state == "on",
                     percent: state == "on" ? brightness.map { Int(($0 / 255.0 * 100).rounded()) } : nil,
                     since: parseOffsetDateTime(o["since"] as? String), rgb: rgb)
    }
}
