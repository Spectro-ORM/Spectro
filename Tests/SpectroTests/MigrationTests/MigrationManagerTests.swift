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

        @Test("Concurrent runners discover pending work only after obtaining ownership")
        func concurrentRunners() async throws {
            try await withFixture { fixture in
                try fixture.write(up: "SELECT pg_sleep(0.3); CREATE TABLE \(fixture.table) (id INT);",
                                  down: "SELECT pg_sleep(0.3); DROP TABLE \(fixture.table);")
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0..<2 { group.addTask { try await fixture.manager.runMigrations() } }
                    try await group.waitForAll()
                }
                #expect(try await fixture.tableExists())
                #expect(try await fixture.status() == .completed)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0..<2 { group.addTask { try await fixture.manager.runRollback() } }
                    try await group.waitForAll()
                }
                #expect(try await !fixture.tableExists())
                #expect(try await fixture.status() == .pending)
            }
        }

        @Test("Migration lock has a bounded wait and frees the single pool slot")
        func lockTimeout() async throws {
            try await withFixture(connections: 1) { fixture in
                let holder = try DatabaseConnection(configuration: fixture.connection.config)
                do {
                    try await holder.executeUpdate(sql: "SELECT pg_advisory_lock(\(MigrationManager.lockKey))")
                    try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                    let manager = MigrationManager(connection: fixture.connection, migrationsPath: fixture.directory,
                                                   lockTimeout: .milliseconds(100))
                    let clock = ContinuousClock(), start = ContinuousClock.now
                    do {
                        try await manager.runMigrations()
                        Issue.record("Expected a migration lock timeout")
                    } catch MigrationError.lockTimeout {}
                    #expect(start.duration(to: clock.now) < .seconds(2))
                    #expect(try await !fixture.tableExists())
                    try await holder.executeUpdate(sql: "SELECT pg_advisory_unlock(\(MigrationManager.lockKey))")
                    try await manager.runMigrations()
                    #expect(try await fixture.tableExists())
                } catch {
                    await holder.shutdown()
                    throw error
                }
                await holder.shutdown()
            }
        }

        @Test("Cancellation releases a waiting migration session")
        func cancelLockWait() async throws {
            try await withFixture(connections: 1) { fixture in
                let holder = try DatabaseConnection(configuration: fixture.connection.config)
                do {
                    try await holder.executeUpdate(sql: "SELECT pg_advisory_lock(\(MigrationManager.lockKey))")
                    try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                    let runner = Task { try await fixture.manager.runMigrations() }
                    try await Task.sleep(for: .milliseconds(100))
                    runner.cancel()
                    do { try await runner.value; Issue.record("Expected cancellation") }
                    catch is CancellationError {}
                    try await holder.executeUpdate(sql: "SELECT pg_advisory_unlock(\(MigrationManager.lockKey))")
                    try await fixture.manager.runMigrations()
                    #expect(try await fixture.tableExists())
                } catch {
                    await holder.shutdown()
                    throw error
                }
                await holder.shutdown()
            }
        }

        @Test("Cancellation interrupts SQL, rolls back, and allows retry")
        func cancelActiveMigration() async throws {
            try await withFixture(connections: 1) { fixture in
                let observer = try DatabaseConnection(configuration: fixture.connection.config)
                try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT); SELECT pg_sleep(20), '\(fixture.table)';",
                                  down: "DROP TABLE \(fixture.table);")
                let runner = Task { try await fixture.manager.runMigrations() }
                do {
                    var sleeping = false
                    for _ in 0..<200 {
                        sleeping = try await observer.executeQuery(
                            sql: "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND query LIKE $1 AND wait_event = 'PgSleep') AS sleeping",
                            parameters: [.init(string: "%\(fixture.table)%")],
                            resultMapper: { $0.makeRandomAccess()[data: "sleeping"].bool == true }
                        ).first == true
                        if sleeping { break }
                        try await Task.sleep(for: .milliseconds(10))
                    }
                    try #require(sleeping, "Migration never reached the long-running statement")
                    // The first runner owns this one-connection pool. A cancelled
                    // queued request must return promptly and release its eventual slot.
                    let queued = Task { try await fixture.manager.runMigrations() }
                    try await Task.sleep(for: .milliseconds(50))
                    let queuedStart = ContinuousClock.now
                    queued.cancel()
                    do { try await queued.value; Issue.record("Expected queued cancellation") }
                    catch is CancellationError {}
                    #expect(queuedStart.duration(to: .now) < .seconds(1))
                    let start = ContinuousClock.now
                    runner.cancel()
                    do { try await runner.value; Issue.record("Expected cancellation") }
                    catch is CancellationError {}
                    #expect(start.duration(to: .now) < .seconds(2))
                    #expect(try await !fixture.tableExists())
                    #expect(try await fixture.status() == nil)
                    try fixture.write(up: "CREATE TABLE \(fixture.table) (id INT);", down: "DROP TABLE \(fixture.table);")
                    let retry = MigrationManager(connection: fixture.connection, migrationsPath: fixture.directory,
                                                 lockTimeout: .seconds(1))
                    try await retry.runMigrations()
                    #expect(start.duration(to: .now) < .seconds(2))
                    #expect(try await fixture.status() == .completed)
                } catch {
                    runner.cancel()
                    _ = await runner.result
                    await observer.shutdown()
                    throw error
                }
                await observer.shutdown()
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
