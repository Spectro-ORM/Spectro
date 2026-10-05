internal enum TableAlteration: Sendable {
    case add(ColumnDefinition)
    case rename(String, String)
}

/// Ordered column additions and renames collected by ``AlterTableBuilder``.
public struct TableAlterations: Sendable {
    internal let changes: [TableAlteration]
    internal init(_ changes: [TableAlteration]) { self.changes = changes }
}

/// Combines column additions and renames for ``AlterTable``.
@resultBuilder
public enum AlterTableBuilder {
    public static func buildExpression(_ column: ColumnDefinition) -> TableAlterations { TableAlterations([.add(column)]) }
    public static func buildExpression(_ changes: TableAlterations) -> TableAlterations { changes }
    public static func buildBlock(_ changes: TableAlterations...) -> TableAlterations { combine(changes) }
    public static func buildOptional(_ changes: TableAlterations?) -> TableAlterations { changes ?? TableAlterations([]) }
    public static func buildEither(first: TableAlterations) -> TableAlterations { first }
    public static func buildEither(second: TableAlterations) -> TableAlterations { second }
    public static func buildArray(_ changes: [TableAlterations]) -> TableAlterations { combine(changes) }
    private static func combine(_ changes: [TableAlterations]) -> TableAlterations { TableAlterations(changes.flatMap(\.changes)) }
}

/// The operation factory supplied to an ``AlterTable`` closure.
public struct AlterTableContext: Sendable {
    internal init() {}
    /// Adds a column, accepting the same modifiers as a new table's columns.
    ///
    /// Automatic rollback drops the column and its data.
    public func add(_ name: String, _ type: MigrationColumnType) -> ColumnDefinition { .init(name: name, type: type) }
    /// Renames a column; automatic rollback restores its previous name.
    public func rename(_ name: String, to newName: String) -> TableAlterations { .init([.rename(name, newName)]) }
}
