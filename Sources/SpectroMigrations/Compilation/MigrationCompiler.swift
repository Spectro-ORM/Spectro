import Spectro
import SpectroCommon

/// Compiles a value plan without connecting to PostgreSQL.
public enum MigrationCompiler {
    public static func prepare<M: Migration>(_ migration: M) throws -> PreparedMigration {
        try prepare(id: M.id, plan: migration.change)
    }

    internal static func prepare(id: String, plan: MigrationPlan) throws -> PreparedMigration {
        guard !plan.operations.isEmpty else { throw MigrationPlanningError(migrationID: id, reason: "Migration is empty") }
        var up: [String] = [], down: [String] = []
        for (position, operation) in plan.operations.enumerated() {
            do {
                let compiled = try compile(operation)
                up.append(contentsOf: compiled.up)
                down.insert(contentsOf: compiled.down, at: 0)
            } catch let error as MigrationPlanningError {
                throw MigrationPlanningError(migrationID: id, operationIndex: position, reason: error.reason)
            }
        }
        let migration = PreparedMigration(version: id, name: String(id.split(separator: "_", maxSplits: 1).last ?? ""),
                                          upSQL: script(up), rollback: .sql(script(down)))
        _ = try MigrationCatalog.load(sources: [.prepared([migration])])
        return migration
    }

    private static func script(_ statements: [String]) -> String { statements.joined(separator: ";\n") + ";" }

    private static func compile(_ operation: MigrationOperation) throws -> (up: [String], down: [String]) {
        typealias SQL = PostgresMigrationRenderer
        switch operation {
        case .createTable(let table):
            let name = try SQL.qualified(table.name, schema: table.schema)
            let columns = table.elements.columns
            guard !columns.isEmpty else { throw MigrationPlanningError(reason: "A table must declare columns") }
            guard Set(columns.map(\.name)).count == columns.count else { throw MigrationPlanningError(reason: "Duplicate column name") }
            guard columns.filter(\.primary).count <= 1 else { throw MigrationPlanningError(reason: "Only one typed primary-key column is supported") }
            let definitions = try columns.map(SQL.column).joined(separator: ",\n  ")
            return (["CREATE TABLE \(name) (\n  \(definitions)\n)"], ["DROP TABLE \(name)"])
        case .alterTable(let table):
            let name = try SQL.qualified(table.name, schema: table.schema)
            guard !table.alterations.changes.isEmpty else { throw MigrationPlanningError(reason: "An alteration must contain changes") }
            var up: [String] = [], down: [String] = []
            var added = Set<String>()
            for change in table.alterations.changes {
                switch change {
                case .add(let column):
                    guard added.insert(column.name).inserted else { throw MigrationPlanningError(reason: "Duplicate added column") }
                    up.append("ALTER TABLE \(name) ADD COLUMN \(try SQL.column(column))")
                    down.insert("ALTER TABLE \(name) DROP COLUMN \(try SQL.identifier(column.name))", at: 0)
                case .rename(let old, let new):
                    let old = try SQL.identifier(old), new = try SQL.identifier(new)
                    up.append("ALTER TABLE \(name) RENAME COLUMN \(old) TO \(new)")
                    down.insert("ALTER TABLE \(name) RENAME COLUMN \(new) TO \(old)", at: 0)
                }
            }
            return (up, down)
        case .createIndex(let index):
            if let issue = index.issues.first { throw MigrationPlanningError(reason: issue) }
            guard !index.columns.isEmpty, Set(index.columns).count == index.columns.count else {
                throw MigrationPlanningError(reason: "An index needs distinct columns")
            }
            let name = try SQL.identifier(index.name)
            let table = try SQL.qualified(index.table, schema: index.schema)
            let columns = try index.columns.map(SQL.identifier).joined(separator: ", ")
            let unique = index.isUnique ? "UNIQUE " : ""
            return (["CREATE \(unique)INDEX \(name) ON \(table) (\(columns))"],
                    ["DROP INDEX \(try SQL.qualified(index.name, schema: index.schema))"])
        }
    }
}

