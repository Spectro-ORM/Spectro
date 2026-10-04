import Foundation
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
        var reasons: [String] = []
        for (position, operation) in plan.operations.enumerated() {
            do {
                let compiled = try automatic(operation)
                up.append(contentsOf: compiled.up)
                down.insert(contentsOf: compiled.down, at: 0)
                reasons.append(contentsOf: compiled.reasons)
            } catch let error as MigrationPlanningError {
                throw MigrationPlanningError(migrationID: id, operationIndex: position, reason: error.reason)
            }
        }
        let migration = PreparedMigration(version: id, name: String(id.split(separator: "_", maxSplits: 1).last ?? ""),
                                          upSQL: script(up), rollback: reasons.isEmpty ? .sql(script(down)) : .irreversible(reason: reasons.joined(separator: "; ")))
        _ = try MigrationCatalog.load(sources: [.prepared([migration])])
        return migration
    }

    private static func script(_ statements: [String]) -> String { statements.joined(separator: ";\n") + ";" }

    private struct Compiled {
        let up: [String]
        let down: [String]
        var reasons: [String] = []
    }

    private static func rawSQL(_ sql: String) throws -> String {
        _ = try MigrationCatalog.load(sources: [.prepared([.init(
            version: "1700000000_fragment", name: "fragment", upSQL: sql, rollback: .sql(sql))])])
        // Keep the generated statement separator outside any trailing line comment.
        return sql + "\n"
    }

    private static func validateReason(_ reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MigrationPlanningError(reason: "An irreversible operation needs a reason")
        }
    }

    private static func automatic(_ operation: MigrationOperation) throws -> Compiled {
        switch operation {
        case .sql(let sql):
            guard let down = sql.down else { throw MigrationPlanningError(reason: "Unpaired SQL requires an explicit branch") }
            return try Compiled(up: [rawSQL(sql.up)], down: [rawSQL(down)])
        case .dropTable:
            throw MigrationPlanningError(reason: "DropTable requires an explicit branch")
        case .reversible(let branches):
            return try Compiled(up: forward(branches.up, isDown: false), down: forward(branches.down, isDown: true))
        case .irreversible(let operation):
            try validateReason(operation.reason)
            return try Compiled(up: forward(operation.body, isDown: false), down: [], reasons: [operation.reason])
        default:
            let result = try ordinary(operation)
            return Compiled(up: result.up, down: result.down)
        }
    }

    // Branch contents are explicit instructions: normal operations execute forward.
    // A nested Reversible selects the same direction, without inverting that branch again.
    private static func forward(_ plan: MigrationPlan, isDown: Bool) throws -> [String] {
        guard !plan.operations.isEmpty else { throw MigrationPlanningError(reason: "An explicit branch must not be empty") }
        return try plan.operations.flatMap { operation -> [String] in
            switch operation {
            case .sql(let sql):
                let up = try rawSQL(sql.up)
                if let down = sql.down { _ = try rawSQL(down) }
                return [up]
            case .dropTable(let table):
                return ["DROP TABLE \(try PostgresMigrationRenderer.qualified(table.name, schema: table.schema))"]
            case .reversible(let branches):
                return try forward(isDown ? branches.down : branches.up, isDown: isDown)
            case .irreversible(let operation):
                guard !isDown else { throw MigrationPlanningError(reason: "Irreversible cannot appear in an explicit down branch") }
                try validateReason(operation.reason)
                return try forward(operation.body, isDown: false)
            default: return try ordinary(operation).up
            }
        }
    }

    private static func ordinary(_ operation: MigrationOperation) throws -> (up: [String], down: [String]) {
        typealias SQL = PostgresMigrationRenderer
        switch operation {
        case .createTable(let table):
            let name = try SQL.qualified(table.name, schema: table.schema)
            let columns = table.elements.columns
            guard !columns.isEmpty else { throw MigrationPlanningError(reason: "A table must declare columns") }
            guard Set(columns.map(\.name)).count == columns.count else { throw MigrationPlanningError(reason: "Duplicate column name") }
            guard columns.filter(\.primary).count <= 1 else { throw MigrationPlanningError(reason: "Only one typed primary-key column is supported") }
            let constraintNames = columns.compactMap { SQL.referenceName($0, table: table.name) } + table.elements.checks.map(\.name)
            guard Set(constraintNames).count == constraintNames.count else { throw MigrationPlanningError(reason: "Duplicate constraint name") }
            let columnSQL = try columns.map { try SQL.column($0, table: table.name) }
            let checks = try table.elements.checks.map { "CONSTRAINT \(try SQL.identifier($0.name)) CHECK (\(try SQL.expression($0.sql)))" }
            let definitions = (columnSQL + checks).joined(separator: ",\n  ")
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
                    up.append("ALTER TABLE \(name) ADD COLUMN \(try SQL.column(column, table: table.name))")
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
            let predicate = try index.predicate.map { " WHERE (\(try SQL.expression($0)))" } ?? ""
            return (["CREATE \(unique)INDEX \(name) ON \(table) (\(columns))\(predicate)"],
                    ["DROP INDEX \(try SQL.qualified(index.name, schema: index.schema))"])
        default: throw MigrationPlanningError(reason: "Expected an ordinary schema operation")
        }
    }
}
