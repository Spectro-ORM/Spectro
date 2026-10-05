import ArgumentParser
@preconcurrency import Noora
import Spectro

struct Rollback: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down", abstract: "Roll back applied migrations in descending ID order.",
        discussion: """
            Omitting --step rolls back all applied migrations. Use --step 1 for only the newest \
            migration; --step 0 rolls back nothing.

            With .spectro.json, launches the project's Swift migration executable, which rejects \
            a selected batch containing missing or irreversible history before any changes. \
            Otherwise, uses SQL files in Sources/Migrations in the current directory. \
            Deleted data is restored only if the migration explicitly provides that recovery.

            Example: spectro migrate down --step 1
            """)

    @Option(name: .long, help: "Number to roll back. Omit for all; zero rolls back nothing.") var step: Int?
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
                message: "Rolling back migrations",
                successMessage: SpectroUI.randomRollbackApplied(),
                errorMessage: "Rollback failed",
                showSpinner: true
            ) { _ in
                try await manager.runRollback(steps: step)
            }
        } catch {
            SpectroUI.noora.error(.alert(
                "Rollback failed",
                takeaways: ["\(.muted(error.localizedDescription))"]
            ))
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }
}
