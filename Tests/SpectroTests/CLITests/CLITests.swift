import Foundation
import Testing

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

    private func run(_ args: [String], env: [String: String]? = nil) throws -> CLIResult {
        let path = try spectroBinaryPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

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
        #expect(result.output.contains("Refusing to drop 'postgres'"))
    }

    @Test("database create refuses 'postgres'")
    func createRefusesPostgres() throws {
        let result = try run(["database", "create", "postgres"])
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Refusing to create 'postgres'"))
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
        #expect(result.output.contains("Invalid database name"))
    }

    @Test("database drop rejects name with quotes")
    func dropRejectsQuoteInjection() throws {
        let result = try run(["database", "drop", "foo\"bar"])
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Invalid database name"))
    }

    // MARK: - Create / Drop Lifecycle

    @Test("database create then drop lifecycle")
    func createAndDropLifecycle() throws {
        // Create
        let createResult = try run(["database", "create", testDB])
        #expect(createResult.exitCode == 0)
        #expect(createResult.output.contains("created successfully"))

        // Create again — should say "already exists", not crash
        let dupeResult = try run(["database", "create", testDB])
        #expect(dupeResult.output.contains("already exists"))

        // Drop
        let dropResult = try run(["database", "drop", testDB])
        #expect(dropResult.exitCode == 0)
        #expect(dropResult.output.contains("dropped successfully"))

        // Drop again — should say "does not exist", not crash
        let dupeDropResult = try run(["database", "drop", testDB])
        #expect(dupeDropResult.output.contains("does not exist"))
    }

    // MARK: - Positional and Flag Args

    @Test("database create works with --database flag too")
    func createWithFlag() throws {
        let createResult = try run(["database", "create", "--database", testDB])
        #expect(createResult.exitCode == 0)
        #expect(createResult.output.contains("created successfully"))

        // Cleanup
        let _ = try run(["database", "drop", testDB])
    }
}
