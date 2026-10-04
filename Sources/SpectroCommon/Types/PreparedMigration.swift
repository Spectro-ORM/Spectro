import Foundation

/// A migration's immutable SQL, independent of its authoring format.
public struct PreparedMigration: Sendable {
    public let version: String
    public let name: String
    public let upSQL: String
    public let rollback: MigrationRollback

    public init(version: String, name: String, upSQL: String, rollback: MigrationRollback) {
        self.version = version
        self.name = name
        self.upSQL = upSQL
        self.rollback = rollback
    }
}

