import Foundation
import Testing
import SpectroCommon
@testable import Spectro

@Suite("Migration catalogs")
struct MigrationCatalogTests {
    private func prepared(_ id: String, sql: String = "SELECT 1") -> PreparedMigration {
        PreparedMigration(version: id, name: "example", upSQL: sql, rollback: .sql("SELECT 2"))
    }

    @Test("SQL resources and prepared definitions share ordering and identity")
    func mixedCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "-- migrate:up\nSELECT 1;\n-- migrate:down\nSELECT 2;".write(
            to: directory.appendingPathComponent("1700000000_a.sql"), atomically: true, encoding: .utf8)
        let b = prepared("1700000000_b")
        let all = try MigrationCatalog.load(sources: [.prepared([b]), .sqlDirectory(directory)])
        #expect(all.map(\.version) == ["1700000000_a", "1700000000_b"])
        #expect(throws: MigrationPlanningError.self) {
            try MigrationCatalog.load(sources: [.sqlDirectory(directory), .prepared([prepared("1700000000_a")])])
        }
    }

    @Test("Empty prepared SQL is rejected", arguments: ["", "   ", "-- only a comment"])
    func emptySQL(sql: String) {
        #expect(throws: MigrationPlanningError.self) {
            try MigrationCatalog.load(sources: [.prepared([prepared("1700000000_empty", sql: sql)])])
        }
    }

    @Test("Prepared migrations cannot take over the transaction", arguments: [
        "COMMIT", "/* comment */ BEGIN", "-- comment\nEND", "START TRANSACTION",
        "ROLLBACK", "ABORT", "SAVEPOINT x", "RELEASE x", "PREPARE TRANSACTION 'x'"
    ])
    func transactionControl(sql: String) {
        #expect(throws: MigrationPlanningError.self) {
            try MigrationCatalog.load(sources: [.prepared([prepared("1700000000_control", sql: sql)])])
        }
    }

    @Test("Procedural BEGIN and quoted semicolons remain valid SQL")
    func proceduralBody() throws {
        let sql = "DO $$ BEGIN PERFORM 'COMMIT;'; END $$; SELECT 'a;b';"
        let all = try MigrationCatalog.load(sources: [.prepared([prepared("1700000000_procedural", sql: sql)])])
        #expect(all.count == 1)
    }
}

extension DatabaseIntegrationTests {
    @Suite("Prepared migration execution")
    struct MigrationRunnerTests {
        struct Fixture {
            let connection: DatabaseConnection
            let suffix: String
            var migrationName: String { "migration_\(suffix)" }
            var a: String { "prepared_\(suffix)_a" }
            var b: String { "prepared_\(suffix)_b" }
            func migration(_ number: Int, up: String, down: MigrationRollback) -> PreparedMigration {
                .init(version: "180000000\(number)_migration_\(suffix)", name: migrationName, upSQL: up, rollback: down)
            }
            func runner(_ migrations: [PreparedMigration], timeout: Duration = .seconds(30)) -> MigrationRunner {
                MigrationRunner(connection: connection, sources: [.prepared(migrations)], lockTimeout: timeout)
            }
            func exists(_ table: String) async throws -> Bool {
                try await connection.executeQuery(
                    sql: "SELECT to_regclass($1) IS NOT NULL AS present", parameters: [.init(string: table)]
                ) { $0.makeRandomAccess()[data: "present"].bool == true }.first == true
            }
        }

        private func withFixture(connections: Int = 1, _ body: (Fixture) async throws -> Void) async throws {
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let connection = try DatabaseConnection(configuration: .init(
                hostname: TestDatabase.hostname, port: TestDatabase.port, username: TestDatabase.username,
                password: TestDatabase.password, database: TestDatabase.database,
                maxConnectionsPerEventLoop: connections, numberOfThreads: 1))
            let fixture = Fixture(connection: connection, suffix: suffix)
            try await MigrationManager(connection: connection).ensureMigrationTableExists()
            do {
                try await body(fixture)
            } catch {
                await cleanup(fixture)
                throw error
            }
            await cleanup(fixture)
        }

        private func cleanup(_ f: Fixture) async {
            try? await f.connection.executeUpdate(sql: "DROP TABLE IF EXISTS \(f.b), \(f.a)")
            try? await f.connection.executeUpdate(sql: "DELETE FROM schema_migrations WHERE name = $1", parameters: [.init(string: f.migrationName)])
            await f.connection.shutdown()
        }

        @Test("Prepared up failure and deferred commit failure leave no schema or completed record")
        func atomicUp() async throws {
            try await withFixture { f in
                for sql in [
                    "CREATE TABLE \(f.a) (id INT); SELECT 1/0",
                    "CREATE TABLE \(f.a) (id INT UNIQUE DEFERRABLE INITIALLY DEFERRED); INSERT INTO \(f.a) VALUES (1),(1)"
                ] {
                    let runner = f.runner([f.migration(0, up: sql, down: .sql("DROP TABLE \(f.a)"))])
                    await #expect(throws: SpectroError.self) { try await runner.runMigrations() }
                    let tableExists = try await f.exists(f.a)
                    let records = try await runner.getMigrationStatus()
                    #expect(!tableExists)
                    #expect(records.filter { $0.name == f.migrationName }.isEmpty)
                }
            }
        }

        @Test("Single-connection up/down/up and failed rollback preserve the ledger")
        func lifecycle() async throws {
            try await withFixture { f in
                let good = f.migration(0, up: "CREATE TABLE \(f.a) (id INT)", down: .sql("DROP TABLE \(f.a)"))
                let runner = f.runner([good])
                try await runner.runMigrations()
                let broken = f.migration(0, up: good.upSQL, down: .sql("DROP TABLE \(f.a); SELECT 1/0"))
                await #expect(throws: SpectroError.self) { try await f.runner([broken]).runRollback(steps: 1) }
                #expect(try await f.exists(f.a))
                #expect(try await runner.getMigrationStatus().first { $0.name == f.migrationName }?.status == .completed)
                try await runner.runRollback(steps: 1)
                #expect(try await !f.exists(f.a))
                try await runner.runMigrations()
                #expect(try await f.exists(f.a))
            }
        }

        @Test("Missing latest history cannot roll back an older entry")
        func missingHistory() async throws {
            try await withFixture { f in
                let a = f.migration(0, up: "CREATE TABLE \(f.a) (id INT)", down: .sql("DROP TABLE \(f.a)"))
                let b = f.migration(1, up: "CREATE TABLE \(f.b) (id INT)", down: .sql("DROP TABLE \(f.b)"))
                try await f.runner([a, b]).runMigrations()
                await #expect(throws: MigrationPlanningError.self) { try await f.runner([a]).runRollback(steps: 1) }
                #expect(try await f.exists(f.a))
                #expect(try await f.exists(f.b))
            }
        }

        @Test("An irreversible selected entry prevents partial rollback")
        func irreversiblePreflight() async throws {
            try await withFixture { f in
                let a = f.migration(0, up: "CREATE TABLE \(f.a) (id INT)", down: .irreversible(reason: "Data retained"))
                let b = f.migration(1, up: "CREATE TABLE \(f.b) (id INT)", down: .sql("DROP TABLE \(f.b)"))
                let runner = f.runner([a, b])
                try await runner.runMigrations()
                await #expect(throws: MigrationPlanningError.self) { try await runner.runRollback() }
                #expect(try await f.exists(f.b))
                try await runner.runRollback(steps: 1)
                #expect(try await !f.exists(f.b))
                #expect(try await f.exists(f.a))
            }
        }


        @Test("Zero rollback does not load or execute a catalog")
        func zeroRollback() async throws {
            try await withFixture { f in
                let runner = MigrationRunner(connection: f.connection,
                    sources: [.sqlDirectory(URL(fileURLWithPath: "/missing/\(UUID())"))])
                try await runner.runRollback(steps: 0)
            }
        }

        @Test("Prepared lock timeout and cancellation release a single pool slot")
        func timeoutAndCancellation() async throws {
            try await withFixture { f in
                let holder = try DatabaseConnection(configuration: f.connection.config)
                let migration = f.migration(0, up: "CREATE TABLE \(f.a) (id INT)", down: .sql("DROP TABLE \(f.a)"))
                do {
                    try await holder.executeUpdate(sql: "SELECT pg_advisory_lock(\(MigrationManager.lockKey))")
                    await #expect(throws: MigrationError.self) {
                        try await f.runner([migration], timeout: .milliseconds(50)).runMigrations()
                    }
                    let waiting = Task { try await f.runner([migration]).runMigrations() }
                    try await Task.sleep(for: .milliseconds(50))
                    waiting.cancel()
                    await #expect(throws: CancellationError.self) { try await waiting.value }
                    try await holder.executeUpdate(sql: "SELECT pg_advisory_unlock(\(MigrationManager.lockKey))")
                    try await f.runner([migration]).runMigrations()
                    #expect(try await f.exists(f.a))
                } catch {
                    await holder.shutdown()
                    throw error
                }
                await holder.shutdown()
            }
        }

        @Test("SQL and prepared concurrent runners execute a shared ID once")
        func concurrency() async throws {
            try await withFixture(connections: 2) { f in
                let migration = f.migration(0, up: "SELECT pg_sleep(0.1); CREATE TABLE \(f.a) (id INT)", down: .sql("DROP TABLE \(f.a)"))
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                try "-- migrate:up\n\(migration.upSQL);\n-- migrate:down\nDROP TABLE \(f.a);".write(
                    to: directory.appendingPathComponent("\(migration.version).sql"), atomically: true, encoding: .utf8)
                let sqlRunner = MigrationRunner(connection: f.connection, sources: [.sqlDirectory(directory)])
                async let first: Void = f.runner([migration]).runMigrations()
                async let second: Void = sqlRunner.runMigrations()
                try await first
                try await second
                #expect(try await f.exists(f.a))
                #expect(try await f.runner([]).getMigrationStatus().filter { $0.name == f.migrationName }.count == 1)
            }
        }
    }
}
