public struct TableElements: Sendable {
    internal let columns: [ColumnDefinition]
    internal init(_ columns: [ColumnDefinition]) { self.columns = columns }
}

@resultBuilder
public enum TableBuilder {
    public static func buildExpression(_ column: ColumnDefinition) -> TableElements { TableElements([column]) }
    public static func buildExpression(_ elements: TableElements) -> TableElements { elements }
    public static func buildBlock(_ elements: TableElements...) -> TableElements { combine(elements) }
    public static func buildOptional(_ elements: TableElements?) -> TableElements { elements ?? TableElements([]) }
    public static func buildEither(first: TableElements) -> TableElements { first }
    public static func buildEither(second: TableElements) -> TableElements { second }
    public static func buildArray(_ elements: [TableElements]) -> TableElements { combine(elements) }
    private static func combine(_ elements: [TableElements]) -> TableElements { TableElements(elements.flatMap(\.columns)) }
}

public struct TableDefinitionContext: Sendable {
    internal init() {}
    public func column(_ name: String, _ type: MigrationColumnType) -> ColumnDefinition { .init(name: name, type: type) }

    /// Insert-time defaults only; no update trigger is created.
    public func timestamps() -> TableElements {
        TableElements(["created_at", "updated_at"].map {
            column($0, .timestamptz).notNull().default(.sql("CURRENT_TIMESTAMP"))
        })
    }
}

