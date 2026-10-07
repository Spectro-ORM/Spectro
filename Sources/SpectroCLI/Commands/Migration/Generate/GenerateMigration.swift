import ArgumentParser
#if RichTerminal
@preconcurrency import Noora
#endif
import Spectro

struct GenerateMigration: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migration", abstract: "Generate a Swift declaration when configured, otherwise a SQL migration.",
        discussion: """
            With .spectro.json, creates <sourceDirectory>/Migrations/<name>.swift without a \
            database connection. Fill in the declaration and add the printed registration line \
            to Migrations.swift. Existing files are never overwritten; registration is explicit.

            Without a descriptor, creates Sources/Migrations/<timestamp>_<snake_case_name>.sql \
            and records it as pending in PostgreSQL. SQL generation requires database access; \
            credential options override .env in the current directory, then process environment.

            Example: spectro generate migration CreateUsers
            """)

    @Argument(help: "Migration name; use PascalCase for Swift, for example CreateUsers.") var name: String
    @Option(name: .long, help: "Database user for SQL generation; unused in Swift mode.") var username: String?
    @Option(name: .long, help: "Database password for SQL generation; unused in Swift mode.") var password: String?
    @Option(name: .long, help: "Database name for SQL generation; unused in Swift mode.") var database: String?

    func run() async throws {
        if let project = try MigrationProject.discover() {
            try SwiftMigrationGenerator.generate(name: name, project: project)
            return
        }
        try await ConfigurationManager.shared.loadEnvFile()
        var overrides: [String: String] = [:]
        if let v = username { overrides["username"] = v }
        if let v = password { overrides["password"] = v }
        if let v = database { overrides["database"] = v }

        let config = await ConfigurationManager.shared.getDatabaseConfig(overrides: overrides)
        let spectro = try SpectroClient(
            hostname: config.hostname, port: config.port,
            username: config.username, password: config.password, database: config.database
        )

        let manager = spectro.migrationManager()
        let generator = MigrationGenerator(migrationManager: manager)
        do {
            try await generator.generate(name: name)
            SpectroUI.noora.success(.alert(
                "Migration \(.primary(name)) created",
                takeaways: [
                    "Edit the migration in \(.muted("Sources/Migrations/"))",
                    "Run \(.command("spectro migrate up")) to apply",
                ]
            ))
        } catch {
            SpectroUI.noora.error(.alert(
                "Failed to generate migration \(.primary(name))",
                takeaways: ["\(.muted("\(error)"))"]
            ))
            await spectro.shutdown()
            throw ExitCode.failure
        }
        await spectro.shutdown()
    }
}
