import ArgumentParser
import Foundation
import Spectro
import SpectroCommon
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The entry point for a project's compiled migration executable.
///
/// Provides `up`, `down`, `status`, and offline `plan` commands over an explicit
/// registry. See <doc:CommandsAndConfiguration> and <doc:Deployment>.
public enum MigrationCommand {
    /// Parses process arguments, installs termination handling, and exits with the command's status.
    ///
    /// - Parameters:
    ///   - migrations: The complete registered history shipped in this executable.
    ///   - configuration: A lazy application configuration provider. When omitted,
    ///     database commands read exported `DB_*` environment variables.
    public static func main(migrations: MigrationRegistry,
                            configuration: (@Sendable () throws -> DatabaseConfiguration)? = nil) async {
        // Linux PID 1 ignores default termination dispositions. These handlers
        // also work when the runner is the container entry point. _exit is signal-safe;
        // closing the process sockets lets PostgreSQL roll back and release ownership.
        signal(SIGINT) { _ in _exit(130) }
        signal(SIGTERM) { _ in _exit(143) }
        let code = await run(arguments: Array(CommandLine.arguments.dropFirst()), migrations: migrations, configuration: configuration)
        exit(code)
    }

    /// Returns an exit status instead of terminating the host process.
    ///
    /// Help and planning do not load database configuration. This entry point does
    /// not install process signal handlers; the embedding application owns lifecycle.
    /// - Parameters:
    ///   - arguments: Command arguments excluding the executable name.
    ///   - migrations: The complete registered history.
    ///   - configuration: Optional lazy database configuration, with credential
    ///     options applied as overrides while preserving TLS and pool settings.
    /// - Returns: Zero on success, or a nonzero command exit status.
    public static func run(arguments: [String], migrations: MigrationRegistry,
                           configuration: (@Sendable () throws -> DatabaseConfiguration)? = nil) async -> Int32 {
        if arguments.isEmpty { print(Root.helpMessage()); return 0 }
        do {
            let command = try Root.parseAsRoot(arguments)
            if let down = command as? Down, down.step == 0 { return 0 }
            if command is Root { print(Root.helpMessage()); return 0 }
            if !(command is Up || command is Down || command is Status || command is Plan) {
                var help = command
                try help.run()
                return 0
            }
            let sources = try migrations.sources()
            let catalog = try MigrationCatalog.load(sources: sources)
            if let plan = command as? Plan {
                let selected: [PreparedMigration]
                if let id = plan.migration {
                    guard let match = catalog.first(where: { $0.version == id }) else {
                        throw ValidationError("Unknown migration ID: \(id)")
                    }
                    selected = [match]
                } else { selected = plan.direction == .down ? Array(catalog.reversed()) : catalog }
                // Preflight the whole preview before printing a partial down plan.
                let scripts = try selected.map { entry -> (String, String) in
                    if plan.direction == .up { return (entry.version, entry.upSQL) }
                    guard case .sql(let sql) = entry.rollback else {
                        if case .irreversible(let reason) = entry.rollback {
                            throw MigrationPlanningError(migrationID: entry.version, reason: "Irreversible: \(reason)")
                        }
                        throw ValidationError("No rollback available")
                    }
                    return (entry.version, sql)
                }
                print("-- Registered migrations (offline), direction: \(plan.direction.rawValue)")
                for (id, sql) in scripts { print("\n-- \(id)\n\(sql)") }
                return 0
            }

            let credentials: MigrationCredentials
            if let up = command as? Up { credentials = up.credentials }
            else if let down = command as? Down { credentials = down.credentials }
            else if let status = command as? Status { credentials = status.credentials }
            else { throw ValidationError("Unknown migration command.") }
            let config = try credentials.resolve(environment: ProcessInfo.processInfo.environment, custom: configuration?())
            let connection = try DatabaseConnection(configuration: config)
            let runner = MigrationRunner(connection: connection, sources: sources)
            do {
                if command is Up {
                    try await runner.runMigrations()
                    print("Migrations applied.")
                } else if let down = command as? Down {
                    try await runner.runRollback(steps: down.step)
                    print("Rollback complete.")
                } else {
                    let records = try await runner.getMigrationStatus()
                    let statuses = Dictionary(uniqueKeysWithValues: records.map { ($0.version, $0.status.rawValue) })
                    for entry in catalog { print("\(entry.version)\t\(statuses[entry.version] ?? "pending")") }
                    let known = Set(catalog.map(\.version))
                    for record in records where !known.contains(record.version) {
                        print("\(record.version)\t\(record.status.rawValue)\tmissing from this artifact")
                    }
                    if records.isEmpty && catalog.isEmpty { print("No migrations registered or applied.") }
                }
            } catch {
                await connection.shutdown()
                throw error
            }
            await connection.shutdown()
            return 0
        } catch {
            let code = Root.exitCode(for: error).rawValue
            let message = Root.fullMessage(for: error)
            if code == 0 { print(message) }
            else { FileHandle.standardError.write(Data((message + "\n").utf8)) }
            return code
        }
    }
}

private struct Root: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "migrations",
        abstract: "Run this project's registered PostgreSQL migrations.",
        discussion: """
            Run plan to preview registered SQL without a database; run status to compare the \
            registry with applied history. Up applies pending IDs; down rolls back completed IDs.

            Database commands use DB_HOST (default localhost), DB_PORT (default 5432), \
            DB_USER, DB_PASSWORD and DB_NAME from process environment. User, password and \
            database are required unless supplied by credential options or the application's \
            configuration provider. .env files are not loaded automatically.

            Deploy this executable with its SQL resource bundles and required runtime libraries. \
            Running the built artifact requires no Swift compiler, SwiftPM or installed spectro CLI.
            """,
        subcommands: [Up.self, Down.self, Status.self, Plan.self])
}
private struct Up: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "up",
        abstract: "Apply pending migrations in ascending ID order.",
        discussion: """
            Completed IDs are skipped. Each migration and its ledger update share a transaction; \
            a failure rolls back that migration while earlier successful migrations remain committed. \
            Uses process environment or the application's configuration provider, plus credential options.
            """)
    @OptionGroup var credentials: MigrationCredentials
}
private struct Down: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "down",
        abstract: "Roll back migrations; omit --step to roll back all.",
        discussion: """
            Rolls back completed IDs in descending order. Missing or irreversible migrations in \
            the selected batch fail preflight before any changes. Use --step 1 for the newest ID. \
            Zero is a no-op without loading database configuration; negative values are rejected. \
            Schema rollback does not recover deleted data unless the migration explicitly does so.
            """)
    @OptionGroup var credentials: MigrationCredentials
    @Option(name: .long, help: "Number to roll back. Zero does nothing; omitted means all.") var step: Int?
    mutating func validate() throws {
        if let step, step < 0 { throw ValidationError("--step cannot be negative.") }
    }
}
private struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status",
        abstract: "Read migration status without creating the ledger.",
        discussion: """
            Requires database access. Reports registered IDs and their status, plus applied IDs \
            missing from this artifact. A fresh database is inspected without creating schema_migrations. \
            Use plan for a preview without a database connection.
            """)
    @OptionGroup var credentials: MigrationCredentials
}
private enum Direction: String, ExpressibleByArgument { case up, down }
private struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "plan",
        abstract: "Preview registered migrations without connecting to PostgreSQL.",
        discussion: """
            Shows all registered migrations, regardless of database status. Up follows ascending \
            IDs; down follows descending IDs and each migration's rollback order. Use --migration \
            to select one full ID. Unknown IDs and irreversible down previews fail before printing \
            a partial plan. Does not load database configuration or check live schema/SQL validity.
            """)
    @Option(name: .long, help: "Preview one full migration ID, including its timestamp and name.") var migration: String?
    @Option(name: .long, help: "SQL direction to preview: up or down.") var direction: Direction = .up
}
