internal enum TableAlteration: Sendable {
    case add(ColumnDefinition)
    case rename(String, String)
}

public struct TableAlterations: Sendable {
    internal let changes: [TableAlteration]
    internal init(_ changes: [TableAlteration]) { self.changes = changes }
}

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

public struct AlterTableContext: Sendable {
    internal init() {}
    public func add(_ name: String, _ type: MigrationColumnType) -> ColumnDefinition { .init(name: name, type: type) }
    public func rename(_ name: String, to newName: String) -> TableAlterations { .init([.rename(name, newName)]) }
}

