import Foundation
import Testing
@testable import Spectro

/// Tests for the `spectro` CLI binary.
/// Spawns the actual executable and verifies output/exit codes.
@Suite("CLI", .serialized)
struct CLITests {

    // MARK: - Helpers

    private func spectroBinaryPath() throws -> String {
        // Walk up from the test bundle to find .build/debug/spectro
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: #file)
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
        try #require(created.exitCode == 0)
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
