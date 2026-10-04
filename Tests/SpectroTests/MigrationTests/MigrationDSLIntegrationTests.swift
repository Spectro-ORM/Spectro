import Foundation
import Testing
import Spectro
import SpectroCommon
import SpectroMigrations

extension DatabaseIntegrationTests {
    @Suite("Swift migration PostgreSQL behavior")
    struct MigrationDSLIntegrationTests {
        struct Tables: Migration {
            static let id = "1900000000_dsl_constraints"
            let parent: String
            let child: String
            let stringMode: String
            var change: MigrationPlan {
                SQL(up: "SET LOCAL standard_conforming_strings = \(stringMode)", down: "SELECT 1")
                CreateTable(parent) { $0.column("id", .integer).primaryKey() }
                CreateTable(child) { table in
                    table.column("id", .integer).primaryKey()
                    table.column("parent_id", .integer).notNull().references(parent, onDelete: .restrict, name: "parent_fk")
                    table.column("title", .text).notNull().default("O'Reilly\\path; -- safe")
                    table.column("empty", .text).default("")
                    table.column("active", .boolean).notNull().default(false)
                    table.column("priority", .integer).notNull().default(0)
                    table.check("priority_check", sql: "priority >= 0")
                }
                CreateIndex("partial_\(child)", on: child, columns: ["title"]).unique().whereSQL("active")
            }
        }

        struct Alteration: Migration {
            static let id = "1900000001_dsl_alteration"
            let table: String
            var change: MigrationPlan {
                AlterTable(table) {
                    $0.rename("title", to: "heading")
                    $0.add("body", .text)
                }
            }
        }

        private func connection() throws -> DatabaseConnection {
            try DatabaseConnection(configuration: .init(
                hostname: TestDatabase.hostname, port: TestDatabase.port, username: TestDatabase.username,
                password: TestDatabase.password, database: TestDatabase.database,
                maxConnectionsPerEventLoop: 1, numberOfThreads: 1))
        }

        @Test("Constraints, defaults and nested reversals execute with a single connection")
        func persistedBehavior() async throws {
            let db = try connection()
            let suffix = UUID().uuidString.prefix(8).lowercased()
            let parent = "dsl_parent_\(suffix)", child = "dsl_child_\(suffix)"
            do {
                for setting in ["on", "off"] {
                    let tables = try MigrationCompiler.prepare(Tables(parent: parent, child: child, stringMode: setting))
                    let alteration = try MigrationCompiler.prepare(Alteration(table: child))
                    let runner = MigrationRunner(connection: db, sources: [.prepared([tables])])
                    try await runner.runMigrations()
                    try await db.executeUpdate(sql: "INSERT INTO \(parent) VALUES (1)")
                    try await db.executeUpdate(sql: "INSERT INTO \(child) (id,parent_id) VALUES (1,1),(2,1)")
                    let values = try await db.executeQuery(sql: "SELECT title,empty FROM \(child) ORDER BY id") {
                        let row = $0.makeRandomAccess()
                        return [row[data: "title"].string, row[data: "empty"].string]
                    }
                    #expect(values == [["O'Reilly\\path; -- safe", ""], ["O'Reilly\\path; -- safe", ""]])
                    for sql in [
                        "INSERT INTO \(child) (id,parent_id) VALUES (3,999)",
                        "INSERT INTO \(child) (id,parent_id,priority) VALUES (3,1,-1)",
                        "DELETE FROM \(parent) WHERE id=1"
                    ] {
                        await #expect(throws: SpectroError.self) { try await db.executeUpdate(sql: sql) }
                    }
                    try await db.executeUpdate(sql: "INSERT INTO \(child) (id,parent_id,active) VALUES (3,1,true)")
                    await #expect(throws: SpectroError.self) {
                        try await db.executeUpdate(sql: "INSERT INTO \(child) (id,parent_id,active) VALUES (4,1,true)")
                    }
                    let all = MigrationRunner(connection: db, sources: [.prepared([tables, alteration])])
                    try await all.runMigrations()
                    try await all.runRollback(steps: 1)
                    let rows = try await db.executeQuery(sql: "SELECT title FROM \(child)") { $0.makeRandomAccess()[data: "title"].string }
                    #expect(rows.count == 3)
                    try await all.runMigrations()
                    try await all.runRollback(steps: 2)
                }
            } catch {
                try? await db.executeUpdate(sql: "DROP TABLE IF EXISTS \(child), \(parent) CASCADE")
                try? await db.executeUpdate(sql: "DELETE FROM schema_migrations WHERE version IN ('\(Tables.id)','\(Alteration.id)')")
                await db.shutdown()
                throw error
            }
            await db.shutdown()
        }

        struct Function: Migration {
            static let id = "1900000002_dsl_function"
            let name: String
            var change: MigrationPlan {
                SQL(up: "CREATE FUNCTION \(name)() RETURNS TEXT AS $$ BEGIN RETURN 'hello;world'; END; $$ LANGUAGE plpgsql",
                    down: "DROP FUNCTION \(name)()")
            }
        }

        @Test("Dollar-quoted SQL executes intact and concurrent indexes remain transactional")
        func rawSQL() async throws {
            let db = try connection()
            let name = "dsl_function_" + UUID().uuidString.prefix(8).lowercased()
            do {
                let function = try MigrationCompiler.prepare(Function(name: name))
                let runner = MigrationRunner(connection: db, sources: [.prepared([function])])
                try await runner.runMigrations()
                let values = try await db.executeQuery(sql: "SELECT \(name)() AS value") { $0.makeRandomAccess()[data: "value"].string }
                #expect(values == ["hello;world"])
                try await runner.runRollback(steps: 1)
                let concurrent = PreparedMigration(version: "1900000003_dsl_concurrent", name: "dsl_concurrent",
                    upSQL: "CREATE TABLE \(name) (id INT); CREATE INDEX CONCURRENTLY \(name)_idx ON \(name) (id)",
                    rollback: .sql("DROP TABLE \(name)"))
                let failing = MigrationRunner(connection: db, sources: [.prepared([concurrent])])
                await #expect(throws: SpectroError.self) { try await failing.runMigrations() }
                let recorded = try await failing.getMigrationStatus().contains { $0.version == concurrent.version }
                #expect(!recorded)
                let exists = try await db.executeQuery(sql: "SELECT to_regclass('\(name)') IS NOT NULL AS present") {
                    $0.makeRandomAccess()[data: "present"].bool
                }
                #expect(exists == [false])
            } catch {
                try? await db.executeUpdate(sql: "DROP FUNCTION IF EXISTS \(name)(); DROP TABLE IF EXISTS \(name)")
                try? await db.executeUpdate(sql: "DELETE FROM schema_migrations WHERE version IN ('\(Function.id)','1900000003_dsl_concurrent')")
                await db.shutdown()
                throw error
            }
            await db.shutdown()
        }
    }
}

