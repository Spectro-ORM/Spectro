import Foundation

public struct MigrationRecord: Sendable {
    public let version: String
    public let name: String
    public let appliedAt: Date
    public let status: MigrationStatus

    public init(version: String, name: String, appliedAt: Date, status: MigrationStatus) {
        self.version = version
        self.name = name
        self.appliedAt = appliedAt
        self.status = status
    }
}
