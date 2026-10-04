public struct MigrationPlan: Sendable {
    internal let operations: [MigrationOperation]
    internal init(_ operations: [MigrationOperation]) { self.operations = operations }
}

internal enum MigrationOperation: Sendable {
    case createTable(CreateTable)
    case alterTable(AlterTable)
    case createIndex(CreateIndex)
}

