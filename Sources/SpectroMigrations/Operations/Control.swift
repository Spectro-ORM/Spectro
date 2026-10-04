/// Explicit branches execute their listed operations in declaration order.
public struct Reversible: MigrationStep {
    internal let up: MigrationPlan
    internal let down: MigrationPlan
    public init(@MigrationBuilder up: () -> MigrationPlan, @MigrationBuilder down: () -> MigrationPlan) {
        self.up = up()
        self.down = down()
    }
    public var migrationPlan: MigrationPlan { MigrationPlan([.reversible(self)]) }
}

public struct Irreversible: MigrationStep {
    internal let reason: String
    internal let body: MigrationPlan
    public init(_ reason: String, @MigrationBuilder _ body: () -> MigrationPlan) {
        self.reason = reason
        self.body = body()
    }
    public var migrationPlan: MigrationPlan { MigrationPlan([.irreversible(self)]) }
}

/// Trusted SQL. A single script is allowed only within an explicit branch.
public struct SQL: MigrationStep {
    internal let up: String
    internal let down: String?
    public init(up: String, down: String) { self.up = up; self.down = down }
    public init(_ sql: String) { up = sql; down = nil }
    public var migrationPlan: MigrationPlan { MigrationPlan([.sql(self)]) }
}

/// Dropping a table requires Reversible or Irreversible; its old shape is not inferred.
public struct DropTable: MigrationStep {
    internal let name: String
    internal let schema: String?
    public init(_ name: String, schema: String? = nil) { self.name = name; self.schema = schema }
    public var migrationPlan: MigrationPlan { MigrationPlan([.dropTable(self)]) }
}

