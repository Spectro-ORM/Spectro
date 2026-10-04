public enum MigrationColumnType: Sendable {
    case uuid, text, integer, bigint, boolean, timestamptz, jsonb
    case varchar(length: Int)
    case numeric(precision: Int, scale: Int)
}

/// Literal defaults stay literals; only .sql opts into a trusted SQL expression.
public enum MigrationDefault: Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String), integer(Int64), floating(Double), boolean(Bool), sql(String)

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .floating(value) }
    public init(booleanLiteral value: Bool) { self = .boolean(value) }
}

public struct ColumnDefinition: Sendable {
    internal let name: String
    internal let type: MigrationColumnType
    internal var primary = false
    internal var required = false
    internal var defaultValue: MigrationDefault?
    internal var reference: ColumnReference?
    internal var modifiers = Set<String>()
    internal var issues: [String] = []

    internal init(name: String, type: MigrationColumnType) { self.name = name; self.type = type }

    public func primaryKey() -> Self { setting("primaryKey") { $0.primary = true } }
    public func notNull() -> Self { setting("notNull") { $0.required = true } }
    public func `default`(_ value: MigrationDefault) -> Self { setting("default") { $0.defaultValue = value } }

    public func references(_ table: String, schema: String? = nil, column: String = "id",
                           onDelete: ReferenceAction = .noAction, name: String? = nil) -> Self {
        setting("references") { $0.reference = .init(table: table, schema: schema, column: column, action: onDelete, name: name) }
    }

    internal func setting(_ key: String, _ change: (inout Self) -> Void) -> Self {
        var copy = self
        if !copy.modifiers.insert(key).inserted { copy.issues.append("Column \(name): \(key) was specified more than once") }
        change(&copy)
        return copy
    }
}

public enum ReferenceAction: String, Sendable {
    case noAction = "NO ACTION"
    case restrict = "RESTRICT"
    case cascade = "CASCADE"
    case setNull = "SET NULL"
    case setDefault = "SET DEFAULT"
}

internal struct ColumnReference: Sendable {
    let table: String
    let schema: String?
    let column: String
    let action: ReferenceAction
    let name: String?
}
