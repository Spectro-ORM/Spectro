import Foundation

/// A discovered SQL migration file and its stable identity.
public struct MigrationFile: Sendable {
    /// The full filename without the `.sql` extension.
    public let version: String
    /// The descriptive portion after the timestamp prefix.
    public let name: String
    /// The location of the SQL file.
    public let filePath: URL

    /// Creates file metadata without reading or executing its contents.
    public init(version: String, name: String, filePath: URL) {
        self.version = version
        self.name = name
        self.filePath = filePath
    }
}
