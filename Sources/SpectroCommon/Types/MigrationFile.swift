import Foundation

public struct MigrationFile: Sendable {
    public let version: String
    public let name: String
    public let filePath: URL

    public init(version: String, name: String, filePath: URL) {
        self.version = version
        self.name = name
        self.filePath = filePath
    }
}
