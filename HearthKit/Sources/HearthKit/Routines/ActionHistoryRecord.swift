import Foundation

/// A single recorded action execution that can contribute to routine learning.
/// Represents one confirmed command (e.g., lock, alarm arm, lights off, garage close) with its timestamp.
public struct ActionHistoryRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let entityIDs: [String]  // Ordered action-set (execution order)
    public let sourceKey: String?    // Stable source marker (e.g., "goodnight", "alarm.arm_night")

    public init(id: UUID = UUID(), timestamp: Date, entityIDs: [String], sourceKey: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.entityIDs = entityIDs
        self.sourceKey = sourceKey
    }
}
