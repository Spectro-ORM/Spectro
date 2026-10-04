import Foundation

public struct MigrationPlanningError: Error, LocalizedError, Sendable {
    public let migrationID: String?
    public let operationIndex: Int?
    public let reason: String

    public init(migrationID: String? = nil, operationIndex: Int? = nil, reason: String) {
        self.migrationID = migrationID
        self.operationIndex = operationIndex
        self.reason = reason
    }

    public var errorDescription: String? {
        let migration = migrationID.map { "Migration \($0): " } ?? ""
        let position = operationIndex.map { "operation \($0): " } ?? ""
        return migration + position + reason
    }
}

