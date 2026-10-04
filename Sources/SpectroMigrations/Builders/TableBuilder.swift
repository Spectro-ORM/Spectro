public struct TableElements: Sendable {
    internal let columns: [ColumnDefinition]
    internal let checks: [TableCheck]
    internal init(_ columns: [ColumnDefinition], checks: [TableCheck] = []) {
        self.columns = columns
        self.checks = checks
    }
}

internal struct TableCheck: Sendable { let name: String; let sql: String }

@resultBuilder
public enum TableBuilder {
    public static func buildExpression(_ column: ColumnDefinition) -> TableElements { TableElements([column]) }
    public static func buildExpression(_ elements: TableElements) -> TableElements { elements }
    public static func buildBlock(_ elements: TableElements...) -> TableElements { combine(elements) }
    public static func buildOptional(_ elements: TableElements?) -> TableElements { elements ?? TableElements([]) }
    public static func buildEither(first: TableElements) -> TableElements { first }
    public static func buildEither(second: TableElements) -> TableElements { second }
    public static func buildArray(_ elements: [TableElements]) -> TableElements { combine(elements) }
    private static func combine(_ elements: [TableElements]) -> TableElements {
        TableElements(elements.flatMap(\.columns), checks: elements.flatMap(\.checks))
    }
}

public struct TableDefinitionContext: Sendable {
    internal init() {}
    public func column(_ name: String, _ type: MigrationColumnType) -> ColumnDefinition { .init(name: name, type: type) }
    public func check(_ name: String, sql: String) -> TableElements { TableElements([], checks: [.init(name: name, sql: sql)]) }

    /// Insert-time defaults only; no update trigger is created.
    public func timestamps() -> TableElements {
        TableElements(["created_at", "updated_at"].map {
            column($0, .timestamptz).notNull().default(.sql("CURRENT_TIMESTAMP"))
        })
    }
}
