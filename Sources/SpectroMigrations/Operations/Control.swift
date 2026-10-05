/// Supplies separate forward and rollback branches.
///
/// Each selected branch executes forward in declaration order. A nested reversible
/// step selects the enclosing direction without automatically inverting it again.
public struct Reversible: MigrationStep {
    internal let up: MigrationPlan
    internal let down: MigrationPlan
    /// Captures nonempty up and down plans without executing SQL.
    public init(@MigrationBuilder up: () -> MigrationPlan, @MigrationBuilder down: () -> MigrationPlan) {
        self.up = up()
        self.down = down()
    }
    public var migrationPlan: MigrationPlan { MigrationPlan([.reversible(self)]) }
}

/// Marks a change that cannot be rolled back and records why.
///
/// The whole migration becomes irreversible. A rollback batch containing it fails
/// preflight before any changes. This step is invalid inside an explicit down branch.
public struct Irreversible: MigrationStep {
    internal let reason: String
    internal let body: MigrationPlan
    /// Captures forward operations and a nonempty explanation of irreversibility.
    public init(_ reason: String, @MigrationBuilder _ body: () -> MigrationPlan) {
        self.reason = reason
        self.body = body()
    }
    public var migrationPlan: MigrationPlan { MigrationPlan([.irreversible(self)]) }
}

/// Trusted PostgreSQL statements executed within the migration's transaction.
///
/// Supply both directions for automatic rollback, or use a single script inside
/// ``Reversible`` or ``Irreversible``. Transaction-control statements are rejected.
public struct SQL: MigrationStep {
    internal let up: String
    internal let down: String?
    /// Captures forward and rollback scripts; neither may be empty.
    public init(up: String, down: String) { self.up = up; self.down = down }
    /// Captures one script, valid only within an explicit branch.
    public init(_ sql: String) { up = sql; down = nil }
    public var migrationPlan: MigrationPlan { MigrationPlan([.sql(self)]) }
}

/// Drops a table inside an explicit reversible or irreversible branch.
///
/// The compiler does not infer the old schema or recover deleted rows. No `CASCADE`
/// or `IF EXISTS` clause is added automatically.
public struct DropTable: MigrationStep {
    internal let name: String
    internal let schema: String?
    /// Declares the table and optional schema to drop.
    public init(_ name: String, schema: String? = nil) { self.name = name; self.schema = schema }
    public var migrationPlan: MigrationPlan { MigrationPlan([.dropTable(self)]) }
}
