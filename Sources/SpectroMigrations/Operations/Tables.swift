public struct CreateTable: MigrationStep {
    internal let name: String
    internal let schema: String?
    internal let elements: TableElements

    public init(_ name: String, schema: String? = nil,
                @TableBuilder _ content: (TableDefinitionContext) -> TableElements) {
        self.name = name
        self.schema = schema
        self.elements = content(TableDefinitionContext())
    }

    public var migrationPlan: MigrationPlan { MigrationPlan([.createTable(self)]) }
}

public struct AlterTable: MigrationStep {
    internal let name: String
    internal let schema: String?
    internal let alterations: TableAlterations

    public init(_ name: String, schema: String? = nil,
                @AlterTableBuilder _ content: (AlterTableContext) -> TableAlterations) {
        self.name = name
        self.schema = schema
        self.alterations = content(AlterTableContext())
    }

    public var migrationPlan: MigrationPlan { MigrationPlan([.alterTable(self)]) }
}

