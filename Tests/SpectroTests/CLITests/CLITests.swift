import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import Spectro

/// Tests for the `spectro` CLI binary.
/// Spawns the actual executable and verifies output/exit codes.
@Suite("CLI", .serialized)
struct CLITests {

    private func startMigration(_ action: String, directory: URL, log: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try spectroBinaryPath())
        process.arguments = ["migrate", action, "--database", testDB]
        process.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment
        env["DB_HOST"] = TestDatabase.hostname
        env["DB_PORT"] = String(TestDatabase.port)
        env["DB_USER"] = TestDatabase.username
        env["DB_PASSWORD"] = TestDatabase.password
        process.environment = env
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        try handle.close()
        return process
    }

    private func waitForExit(_ process: Process) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while process.isRunning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!process.isRunning, "Migration process did not exit within 10 seconds")
    }

    private func finish(_ processes: [Process]) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while processes.contains(where: \.isRunning) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        for process in processes {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                Issue.record("Migration process timed out")
            }
            try await waitForExit(process)
            #expect(process.terminationStatus == 0)
        }
    }

    @Test("Separate CLI processes serialize fresh bootstrap, up, and down")
    func concurrentMigrationProcesses() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spectro-processes-\(UUID())")
        let migrations = directory.appendingPathComponent("Sources/Migrations")
        try FileManager.default.createDirectory(at: migrations, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
            -- migrate:up
            SELECT pg_sleep(0.3);
            CREATE TABLE cli_race (id INT PRIMARY KEY);
            INSERT INTO cli_race VALUES (1);
            -- migrate:down
            SELECT pg_sleep(0.3);
            DROP TABLE cli_race;
            """.write(to: migrations.appendingPathComponent("1700000000_race.sql"), atomically: true, encoding: .utf8)
        let didCreate: Bool = try run(["database", "create", testDB], directory: directory).exitCode == 0
        try #require(didCreate)
        defer { _ = try? run(["database", "drop", "--force", testDB], directory: directory) }
        for action in ["up", "down", "up"] {
            let first = try startMigration(action, directory: directory, log: directory.appendingPathComponent("first.log"))
            let second = try startMigration(action, directory: directory, log: directory.appendingPathComponent("second.log"))
            try await finish([first, second])
            let status = try run(["migrate", "status", "--database", testDB], directory: directory)
            #expect(status.output.contains(action == "up" ? "1 applied" : "1 pending"), "\(status.output)")
        }
    }

    @Test("Terminating a migration process rolls back and releases ownership")
    func terminatedMigrationProcess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spectro-killed-\(UUID())")
        let migrations = directory.appendingPathComponent("Sources/Migrations")
        try FileManager.default.createDirectory(at: migrations, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = migrations.appendingPathComponent("1700000000_killed.sql")
        try """
            -- migrate:up
            CREATE TABLE cli_killed (id INT);
            SELECT pg_sleep(20), 'spectro_kill_probe';
            -- migrate:down
            DROP TABLE cli_killed;
            """.write(to: file, atomically: true, encoding: .utf8)
        let didCreate: Bool = try run(["database", "create", testDB], directory: directory).exitCode == 0
        try #require(didCreate)
        defer { _ = try? run(["database", "drop", "--force", testDB], directory: directory) }
        let observer = try DatabaseConnection(configuration: .init(
            hostname: TestDatabase.hostname, port: TestDatabase.port, username: TestDatabase.username,
            password: TestDatabase.password, database: testDB, maxConnectionsPerEventLoop: 1, numberOfThreads: 1
        ))
        let runner = try startMigration("up", directory: directory, log: directory.appendingPathComponent("killed.log"))
        do {
            var sleeping = false
            for _ in 0..<300 {
                sleeping = try await observer.executeQuery(
                    sql: "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND query LIKE '%spectro_kill_probe%' AND wait_event = 'PgSleep') AS sleeping",
                    resultMapper: { $0.makeRandomAccess()[data: "sleeping"].bool == true }
                ).first == true
                if sleeping { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(sleeping)
            let killedSuccessfully = kill(runner.processIdentifier, SIGKILL) == 0
            try #require(killedSuccessfully)
            try await waitForExit(runner)
            #expect(runner.terminationReason == .uncaughtSignal)
            #expect(runner.terminationStatus == SIGKILL)
            try """
                -- migrate:up
                CREATE TABLE cli_killed (id INT);
                -- migrate:down
                DROP TABLE cli_killed;
                """.write(to: file, atomically: true, encoding: .utf8)
            let retry = try startMigration("up", directory: directory, log: directory.appendingPathComponent("retry.log"))
            try await finish([retry])
            let status = try run(["migrate", "status", "--database", testDB], directory: directory)
            #expect(status.output.contains("1 applied"))
        } catch {
            if runner.isRunning {
                kill(runner.processIdentifier, SIGKILL)
                try? await waitForExit(runner)
            }
            await observer.shutdown()
            throw error
        }
        await observer.shutdown()
    }

    // MARK: - Helpers

    private func spectroBinaryPath() throws -> String {
        if let path = ProcessInfo.processInfo.environment["SPECTRO_CLI_PATH"] { return path }
        // Walk up from the test bundle to find .build/debug/spectro
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // CLITests/
            .deletingLastPathComponent() // SpectroTests/
            .deletingLastPathComponent() // Tests/
        let candidate = dir.appendingPathComponent(".build/debug/spectro").path
        if fm.fileExists(atPath: candidate) {
            return candidate
        }
        // Fallback: check current directory
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let fallback = cwd.appendingPathComponent(".build/debug/spectro").path
        if fm.fileExists(atPath: fallback) {
            return fallback
        }
        throw CLITestError.binaryNotFound
    }

    enum CLITestError: Error {
        case binaryNotFound
    }

    struct CLIResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var output: String { stdout + stderr }
    }

    private func run(_ args: [String], env: [String: String]? = nil, directory: URL? = nil) throws -> CLIResult {
        let path = try spectroBinaryPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.currentDirectoryURL = directory

        var environment = ProcessInfo.processInfo.environment
        environment["DB_HOST"] = environment["DB_HOST"] ?? "localhost"
        environment["DB_PORT"] = environment["DB_PORT"] ?? "5432"
        environment["DB_USER"] = environment["DB_USER"] ?? "postgres"
        environment["DB_PASSWORD"] = environment["DB_PASSWORD"] ?? "postgres"
        if let extra = env {
            for (k, v) in extra { environment[k] = v }
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private let testDB = "spectro_cli_test_\(UUID().uuidString.prefix(8).lowercased())"

    // MARK: - Help

    @Test("--help shows usage")
    func helpOutput() throws {
        let result = try run(["--help"])
        #expect(result.exitCode == 0)
        #expect(result.output.contains("USAGE: spectro"))
        #expect(result.output.contains("database"))
        #expect(result.output.contains("migrate"))
    }

    @Test("database --help shows subcommands")
    func databaseHelp() throws {
        let result = try run(["database", "--help"])
        #expect(result.exitCode == 0)
        #expect(result.output.contains("create"))
        #expect(result.output.contains("drop"))
    }

    // MARK: - Safety Guards

    @Test("database drop refuses 'postgres'")
    func dropRefusesPostgres() throws {
        let result = try run(["database", "drop", "postgres"])
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Refusing to drop"))
    }

    @Test("database create refuses 'postgres'")
    func createRefusesPostgres() throws {
        let result = try run(["database", "create", "postgres"])
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Refusing to create"))
    }

    @Test("database drop without name shows usage")
    func dropRequiresName() throws {
        let result = try run(["database", "drop"])
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Database name is required"))
    }

    @Test("database create without name shows usage")
    func createRequiresName() throws {
        let result = try run(["database", "create"])
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Database name is required"))
    }

    // MARK: - SQL Injection Guard

    @Test("database create rejects name with special characters")
    func createRejectsInjection() throws {
        let result = try run(["database", "create", "foo; DROP TABLE users;--"])
        #expect(result.exitCode != 0)
        // ValidationError is formatted by ArgumentParser; check for error indicator
        #expect(result.output.contains("Error") || result.output.contains("ValidationError"))
    }

    @Test("database drop rejects name with quotes")
    func dropRejectsQuoteInjection() throws {
        let result = try run(["database", "drop", "foo\"bar"])
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Error") || result.output.contains("ValidationError"))
    }

    // MARK: - Create / Drop Lifecycle

    @Test("Migration commands work on a fresh database", arguments: ["up", "down", "status"])
    func freshMigrationDatabase(firstCommand: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spectro-cli-\(UUID().uuidString)")
        let migrations = directory.appendingPathComponent("Sources/Migrations")
        try FileManager.default.createDirectory(at: migrations, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
            -- migrate:up
            CREATE TABLE cli_migration (id INT);
            -- migrate:down
            DROP TABLE cli_migration;
            """.write(to: migrations.appendingPathComponent("1700000000_cli.sql"), atomically: true, encoding: .utf8)

        let created = try run(["database", "create", testDB], directory: directory)
        let didCreate: Bool = created.exitCode == 0
        try #require(didCreate)
        defer { _ = try? run(["database", "drop", "--force", testDB], directory: directory) }
        let initial = try run(["migrate", firstCommand, "--database", testDB], directory: directory)
        #expect(initial.exitCode == 0, "\(initial.output)")
        let up = try run(["migrate", "up", "--database", testDB], directory: directory)
        #expect(up.exitCode == 0, "\(up.output)")
        // New connections inherit read-only mode. Status must not try to create tracking objects.
        let control = try DatabaseConnection(configuration: .init(
            hostname: TestDatabase.hostname, port: TestDatabase.port,
            username: TestDatabase.username, password: TestDatabase.password,
            database: testDB, maxConnectionsPerEventLoop: 1, numberOfThreads: 1
        ))
        let applied: CLIResult
        do {
            try await control.executeUpdate(sql: "ALTER DATABASE \"\(testDB)\" SET default_transaction_read_only = on")
            applied = try run(["migrate", "status", "--database", testDB], directory: directory)
            try await control.executeUpdate(sql: "ALTER DATABASE \"\(testDB)\" RESET default_transaction_read_only")
        } catch {
            try? await control.executeUpdate(sql: "ALTER DATABASE \"\(testDB)\" RESET default_transaction_read_only")
            await control.shutdown()
            throw error
        }
        await control.shutdown()
        #expect(applied.exitCode == 0)
        #expect(applied.output.contains("1 applied"))
        let down = try run(["migrate", "down", "--step", "1", "--database", testDB], directory: directory)
        #expect(down.exitCode == 0, "\(down.output)")
        let pending = try run(["migrate", "status", "--database", testDB], directory: directory)
        #expect(pending.exitCode == 0)
        #expect(pending.output.contains("1 pending"))
    }

    @Test("database create then drop lifecycle")
    func createAndDropLifecycle() throws {
        // Create
        let createResult = try run(["database", "create", testDB])
        #expect(createResult.exitCode == 0)
        #expect(createResult.output.contains("created successfully"))

        // Create again — should say "already exists", not crash
        let dupeResult = try run(["database", "create", testDB])
        #expect(dupeResult.output.contains("already exists"))

        // Drop (--force skips interactive confirmation prompt)
        let dropResult = try run(["database", "drop", "--force", testDB])
        #expect(dropResult.exitCode == 0)
        #expect(dropResult.output.contains("dropped successfully"))

        // Drop again — should say "does not exist", not crash
        let dupeDropResult = try run(["database", "drop", "--force", testDB])
        #expect(dupeDropResult.output.contains("does not exist"))
    }

    // MARK: - Positional and Flag Args

    @Test("database create works with --database flag too")
    func createWithFlag() throws {
        let createResult = try run(["database", "create", "--database", testDB])
        #expect(createResult.exitCode == 0)
        #expect(createResult.output.contains("created successfully"))

        // Cleanup
        let _ = try run(["database", "drop", "--force", testDB])
    }
}
