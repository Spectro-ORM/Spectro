/// Column and check-constraint declarations collected by ``TableBuilder``.
public struct TableElements: Sendable {
    internal let columns: [ColumnDefinition]
    internal let checks: [TableCheck]
    internal init(_ columns: [ColumnDefinition], checks: [TableCheck] = []) {
        self.columns = columns
        self.checks = checks
    }
}

internal struct TableCheck: Sendable { let name: String; let sql: String }

/// Collects columns, timestamp helpers, and checks for ``CreateTable``.
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

/// The column and constraint factory supplied to a ``CreateTable`` closure.
public struct TableDefinitionContext: Sendable {
    internal init() {}
    /// Declares a nullable column; use modifiers to add constraints or a default.
    public func column(_ name: String, _ type: MigrationColumnType) -> ColumnDefinition { .init(name: name, type: type) }
    /// Declares a named check using a trusted PostgreSQL expression.
    public func check(_ name: String, sql: String) -> TableElements { TableElements([], checks: [.init(name: name, sql: sql)]) }

    /// Adds `created_at` and `updated_at` as nonnullable timestamp-with-time-zone columns.
    ///
    /// Both default to `CURRENT_TIMESTAMP` on insert. No update trigger is created.
    public func timestamps() -> TableElements {
        TableElements(["created_at", "updated_at"].map {
            column($0, .timestamptz).notNull().default(.sql("CURRENT_TIMESTAMP"))
        })
    }
}
