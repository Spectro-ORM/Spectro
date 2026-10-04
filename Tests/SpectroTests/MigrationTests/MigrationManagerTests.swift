import Foundation
import Testing
import SpectroCommon
@testable import Spectro

extension DatabaseIntegrationTests {
    @Suite("Migration atomicity")
    struct MigrationManagerTests {
        private struct Fixture {
            let connection: DatabaseConnection
            let directory: URL
            let table: String
            let version: String

            var manager: MigrationManager {
                MigrationManager(connection: connection, migrationsPath: directory)
            }

            func write(up: String, down: String) throws {
                try "-- migrate:up\n\(up)\n-- migrate:down\n\(down)\n".write(
                    to: directory.appendingPathComponent("\(version).sql"),
                    atomically: true, encoding: .utf8
                )
            }

            func tableExists() async throws -> Bool {
                try await connection.executeQuery(
                    sql: "SELECT to_regclass($1) IS NOT NULL AS present",
                    parameters: [.init(string: table)],
                    resultMapper: { $0.makeRandomAccess()[data: "present"].bool ?? false }
                ).first ?? false
            }

            func status() async throws -> MigrationStatus? {
                try await manager.getMigrationStatus().first { $0.version == version }?.status
            }
        }

        private func withFixture(
            connections: Int = 2, _ body: (Fixture) async throws -> Void
        ) async throws {
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spectro-migration-\(suffix)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let connection = try DatabaseConnection(configuration: .init(
                hostname: TestDatabase.hostname, port: TestDatabase.port,
                username: TestDatabase.username, password: TestDatabase.password,
                database: TestDatabase.database, maxConnectionsPerEventLoop: connections, numberOfThreads: 1
            ))
            let fixture = Fixture(connection: connection, directory: directory,
                                  table: "migration_\(suffix)", version: "1700000000_\(suffix)")
            do {
                try await fixture.manager.ensureMigrationTableExists()
                try await body(fixture)
            } catch {
                await cleanup(fixture)
                throw error
            }
            await cleanup(fixture)
        }

        private func cleanup(_ fixture: Fixture) async {
            try? await fixture.connection.executeUpdate(
                sql: "ALTER TABLE schema_migrations DROP CONSTRAINT IF EXISTS \(fixture.table)_tracking"
            )
            try? await fixture.connection.executeUpdate(sql: "DROP TABLE IF EXISTS \(fixture.table)")
            try? await fixture.connection.executeUpdate(
                sql: "DELETE FROM schema_migrations WHERE version = $1", parameters: [.init(string: fixture.version)]
            )
            await fixture.connection.shutdown()
        }

        @Test("Failed up rolls back DDL and remains retryable")
        func failedUp() async throws {
            try await withFixture { fixture in
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT); SELECT 1 / 0;",
                                  down: "DROP TABLE \(fixture.table);")
                do {
                    try await fixture.manager.runMigrations()
                    Issue.record("Expected migration failure")
                } catch {}
                #expect(try await !fixture.tableExists())
                #expect(try await fixture.status() == nil)
                // Retry the same version after correcting the SQL.
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                try await fixture.manager.runMigrations()
                #expect(try await fixture.tableExists())
                #expect(try await fixture.status() == .completed)
            }
        }

        @Test("Failed down preserves the table and completed status")
        func failedDown() async throws {
            try await withFixture { fixture in
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);",
                                  down: "DROP TABLE \(fixture.table); SELECT 1 / 0;")
                try await fixture.manager.runMigrations()
                do {
                    try await fixture.manager.runRollback(steps: 1)
                    Issue.record("Expected rollback failure")
                } catch {}
                #expect(try await fixture.tableExists())
                #expect(try await fixture.status() == .completed)
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                try await fixture.manager.runRollback(steps: 1)
                #expect(try await !fixture.tableExists())
                #expect(try await fixture.status() == .pending)
            }
        }

        @Test("Failed commit rolls back DDL and tracking together")
        func failedCommit() async throws {
            try await withFixture { fixture in
                // A deferred constraint fails at COMMIT, after the status was written.
                try fixture.write(up: """
                    CREATE TABLE \(fixture.table) (id INT UNIQUE DEFERRABLE INITIALLY DEFERRED);
                    INSERT INTO \(fixture.table) VALUES (1), (1);
                    """, down: "DROP TABLE \(fixture.table);")
                do {
                    try await fixture.manager.runMigrations()
                    Issue.record("Expected deferred constraint failure")
                } catch {}
                #expect(try await !fixture.tableExists())
                #expect(try await fixture.status() == nil)
            }
        }

        @Test("Failed completed-status write rolls back up SQL")
        func failedUpTracking() async throws {
            try await withFixture { fixture in
                try await fixture.connection.executeUpdate(sql: """
                    ALTER TABLE schema_migrations ADD CONSTRAINT \(fixture.table)_tracking
                    CHECK (version <> '\(fixture.version)')
                    """)
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                do {
                    try await fixture.manager.runMigrations()
                    Issue.record("Expected status write failure")
                } catch {}
                #expect(try await !fixture.tableExists())
                #expect(try await fixture.status() == nil)
            }
        }

        @Test("Failed pending-status write rolls back down SQL")
        func failedDownTracking() async throws {
            try await withFixture { fixture in
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                try await fixture.manager.runMigrations()
                try await fixture.connection.executeUpdate(sql: """
                    ALTER TABLE schema_migrations ADD CONSTRAINT \(fixture.table)_tracking
                    CHECK (version <> '\(fixture.version)' OR status = 'completed')
                    """)
                do {
                    try await fixture.manager.runRollback(steps: 1)
                    Issue.record("Expected status write failure")
                } catch {}
                #expect(try await fixture.tableExists())
                #expect(try await fixture.status() == .completed)
            }
        }

        @Test("Migration lifecycle works with a single pooled connection")
        func singleConnectionLifecycle() async throws {
            try await withFixture(connections: 1) { fixture in
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                try await fixture.manager.runMigrations()
                #expect(try await fixture.tableExists())
                #expect(try await fixture.status() == .completed)
                try await fixture.manager.runRollback(steps: 1)
                #expect(try await !fixture.tableExists())
                #expect(try await fixture.status() == .pending)
                try await fixture.manager.runMigrations()
                #expect(try await fixture.tableExists())
                #expect(try await fixture.status() == .completed)
            }
        }

        @Test("Migration status remains readable on a read-only connection")
        func readOnlyStatus() async throws {
            try await withFixture(connections: 1) { fixture in
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                try await fixture.manager.runMigrations()
                try await fixture.connection.executeUpdate(sql: "SET default_transaction_read_only = on")
                do {
                    let (_, statuses) = try await fixture.manager.getMigrationStatuses()
                    #expect(statuses[fixture.version] == .completed)
                } catch {
                    try await fixture.connection.executeUpdate(sql: "SET default_transaction_read_only = off")
                    throw error
                }
                try await fixture.connection.executeUpdate(sql: "SET default_transaction_read_only = off")
            }
        }
    }
}
