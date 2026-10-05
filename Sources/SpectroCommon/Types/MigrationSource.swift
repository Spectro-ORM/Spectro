import Foundation

/// An input to the shared catalog, independent of authoring language.
public enum MigrationSource: Sendable {
    /// A directory of historical `.sql` files with up and down section markers.
    case sqlDirectory(URL)
    /// Immutable definitions already expressed as SQL and rollback metadata.
    case prepared([PreparedMigration])
}
