#if DEBUG
import Foundation
import HearthKit

/// Intercepts every Home Assistant request the app sends through `URLSession.shared` (HaClient's
/// default transport, and HaAuth's `/auth/token`) and answers with the fictional house's canned data.
/// Registered globally with `URLProtocol.registerClass` by DemoHouse; only claims requests to the
/// demo host, so all other traffic is untouched. DEBUG only.
final class DemoHouseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == DemoHouseCatalog.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, body) = Self.respond(path: url.path, method: request.httpMethod ?? "GET",
                                           body: Self.bodyString(from: request))
        let headers = ["Content-Type": "application/json"]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // MARK: - Routing

    private static func respond(path: String, method: String, body: String) -> (Int, String) {
        if path == "/api/states" { return (200, DemoHouseCatalog.serializeStates()) }
        if path.hasPrefix("/api/states/") {
            let id = String(path.dropFirst("/api/states/".count))
            guard let object = DemoHouseCatalog.stateObject(for: id),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let json = String(data: data, encoding: .utf8) else {
                return (404, #"{"message":"Entity not found."}"#)
            }
            return (200, json)
        }
        if path == "/api/template" { return (200, templateResult(for: body)) }
        if path.hasPrefix("/api/services/") { return (200, "[]") }           // changed-states array; nothing re-read needs it
        if path.hasPrefix("/api/logbook/") { return (200, DemoHouseCatalog.logbookResult) }
        if path == "/auth/token" {                                           // not normally hit (long-lived token set)
            return (200, #"{"access_token":"demo-house-access-token","expires_in":1800,"token_type":"Bearer"}"#)
        }
        return (200, "{}")
    }

    /// `/api/template` sends the Jinja source in `{"template": "…"}`. Match the three templates the
    /// dashboard uses by a distinctive substring; anything else gets an inert empty body.
    private static func templateResult(for body: String) -> String {
        let template = extractTemplate(from: body) ?? body
        if template.contains("_battery_range") { return DemoHouseCatalog.carTemplateResult }
        if template.contains("states.light") { return DemoHouseCatalog.lightsTemplateResult }
        if template.contains("device_class == 'battery'") { return DemoHouseCatalog.batteryTemplateResult }
        return "{}"                                                          // e.g. commute template → parses to nil, safely skipped
    }

    private static func extractTemplate(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["template"] as? String
    }

    /// URLSession hands POST bodies to a protocol as a stream, so read either representation.
    private static func bodyString(from request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DemoHouseCatalog {
    static func serializeStates() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: allStateObjects),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}
#endif
