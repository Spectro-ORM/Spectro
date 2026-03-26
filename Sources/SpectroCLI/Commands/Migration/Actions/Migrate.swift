import ArgumentParser
@preconcurrency import Noora
import Spectro

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "up")

    @Option(name: .long, help: "Database Username") var username: String?
    @Option(name: .long, help: "Database Password") var password: String?
    @Option(name: .long, help: "Database Name")     var database: String?

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
            let pending = try await manager.getPendingMigrations()
            guard !pending.isEmpty else {
                SpectroUI.noora.info(.alert(
                    "No pending migrations.",
                    takeaways: ["Run \(.command("spectro migrate status")) to see current state"]
                ))
                await spectro.shutdown()
                return
            }

            try await SpectroUI.noora.progressStep(
                message: "Applying \(pending.count) migration(s)",
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
