import Foundation

/// A migration's immutable SQL, independent of its authoring format.
public struct PreparedMigration: Sendable {
    /// The stable full migration ID used as the ledger key.
    public let version: String
    /// The descriptive migration name, separate from its full ID.
    public let name: String
    /// PostgreSQL statements to execute when applying the migration.
    public let upSQL: String
    /// Reverse SQL or an explicit reason the migration cannot be rolled back.
    public let rollback: MigrationRollback

    /// Stores a definition; validation happens when the migration catalog loads it.
    public init(version: String, name: String, upSQL: String, rollback: MigrationRollback) {
        self.version = version
        self.name = name
        self.upSQL = upSQL
        self.rollback = rollback
    }
}
