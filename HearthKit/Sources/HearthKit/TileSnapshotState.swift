import Foundation

/// Empty content is not sufficient to tell whether a widget has been read successfully.
public enum TileSnapshotState: Sendable, Equatable {
    case setup, choose, loading, ready, empty, failed
}

func tileReadError(_ error: Error) -> String {
    if let ha = error as? HaError { return ha.message }
    return "Can't reach Home Assistant"
}

func tileStateObject(_ json: String, id: String) throws -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["entity_id"] as? String == id, object["state"] is String else {
        throw HaError("Unexpected entity reading")
    }
    return object
}
