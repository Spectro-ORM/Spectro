import Foundation

/// A migration's identity, timestamp, and status as represented in the ledger.
public struct MigrationRecord: Sendable {
    /// The full migration ID stored as the ledger key.
    public let version: String
    /// The descriptive migration name.
    public let name: String
    /// The timestamp recorded with this ledger entry.
    public let appliedAt: Date
    /// The recorded state; use this field to determine whether the migration completed.
    public let status: MigrationStatus

    /// Creates an immutable ledger value.
    public init(version: String, name: String, appliedAt: Date, status: MigrationStatus) {
        self.version = version
        self.name = name
        self.appliedAt = appliedAt
        self.status = status
    }
}
