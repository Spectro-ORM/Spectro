public struct CreateIndex: MigrationStep {
    internal let name: String
    internal let table: String
    internal let columns: [String]
    internal let schema: String?
    internal var isUnique = false
    internal var predicate: String?
    internal var issues: [String] = []

    public init(_ name: String, on table: String, columns: [String], schema: String? = nil) {
        self.name = name
        self.table = table
        self.columns = columns
        self.schema = schema
    }

    public func unique() -> Self {
        var copy = self
        if copy.isUnique { copy.issues.append("Index uniqueness was specified more than once") }
        copy.isUnique = true
        return copy
    }

    public var migrationPlan: MigrationPlan { MigrationPlan([.createIndex(self)]) }

    public func whereSQL(_ expression: String) -> Self {
        var copy = self
        if copy.predicate != nil { copy.issues.append("Index predicate was specified more than once") }
        copy.predicate = expression
        return copy
    }
}
