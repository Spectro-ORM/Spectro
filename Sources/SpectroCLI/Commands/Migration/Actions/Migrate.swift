import ArgumentParser
@preconcurrency import Noora
import Spectro

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up", abstract: "Apply all pending migrations in ascending ID order.",
        discussion: """
            With .spectro.json, launches the project's Swift migration executable. Otherwise, \
            reads SQL files from Sources/Migrations in the current directory.

            Each migration and its ledger update share a transaction. A failing migration rolls \
            back its changes; earlier successful migrations remain committed. Completed IDs are skipped. \
            Use 'spectro migrate status' to inspect progress or 'spectro help migrate' for configuration.
            """)

    @Option(name: .long, help: "Override the configured database user (DB_USER).") var username: String?
    @Option(name: .long, help: "Override the configured database password (DB_PASSWORD).") var password: String?
    @Option(name: .long, help: "Override the configured database name (DB_NAME).") var database: String?

    func run() async throws {
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
        do {
            try await SpectroUI.noora.progressStep(
                message: "Applying pending migrations",
                successMessage: SpectroUI.randomMigrationApplied(),
                errorMessage: "Migration failed",
                showSpinner: true
            ) { _ in
                try await manager.runMigrations()
            }
        } catch {
            SpectroUI.noora.error(.alert(
                "Migration failed",
                takeaways: ["\(.muted(error.localizedDescription))"]
            ))
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }
}
