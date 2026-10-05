/// Creates a named B-tree index with an automatically generated drop for rollback.
public struct CreateIndex: MigrationStep {
    internal let name: String
    internal let table: String
    internal let columns: [String]
    internal let schema: String?
    internal var isUnique = false
    internal var predicate: String?
    internal var issues: [String] = []

    /// Declares an index over one or more column identifiers on the named table.
    public init(_ name: String, on table: String, columns: [String], schema: String? = nil) {
        self.name = name
        self.table = table
        self.columns = columns
        self.schema = schema
    }

    /// Returns a declaration that enforces uniqueness across the indexed columns.
    public func unique() -> Self {
        var copy = self
        if copy.isUnique { copy.issues.append("Index uniqueness was specified more than once") }
        copy.isUnique = true
        return copy
    }

    public var migrationPlan: MigrationPlan { MigrationPlan([.createIndex(self)]) }

    /// Restricts the index to rows matching a trusted PostgreSQL predicate.
    ///
    /// The expression is inserted as SQL. Do not pass user input.
    public func whereSQL(_ expression: String) -> Self {
        var copy = self
        if copy.predicate != nil { copy.issues.append("Index predicate was specified more than once") }
        copy.predicate = expression
        return copy
    }
}
