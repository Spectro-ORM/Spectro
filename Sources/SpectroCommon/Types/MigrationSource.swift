import Foundation

public enum MigrationSource: Sendable {
    case sqlDirectory(URL)
    case prepared([PreparedMigration])
}

