import Foundation

/// A migration definition or catalog error found before database execution.
public struct MigrationPlanningError: Error, LocalizedError, Sendable {
    /// The affected full migration ID, when known.
    public let migrationID: String?
    /// The zero-based operation or statement position at the reporting stage.
    public let operationIndex: Int?
    /// The explanation of the invalid or unsupported definition.
    public let reason: String

    /// Creates a diagnostic with optional migration and position context.
    public init(migrationID: String? = nil, operationIndex: Int? = nil, reason: String) {
        self.migrationID = migrationID
        self.operationIndex = operationIndex
        self.reason = reason
    }

    /// A readable diagnostic combining available context with the reason.
    public var errorDescription: String? {
        let migration = migrationID.map { "Migration \($0): " } ?? ""
        let position = operationIndex.map { "operation \($0): " } ?? ""
        return migration + position + reason
    }
}
