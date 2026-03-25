import ArgumentParser
import Spectro

struct GenerateMigration: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "migration")

    @Argument(help: "Name of the migration") var name: String
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
        let generator = MigrationGenerator(migrationManager: manager)
        do {
            try await generator.generate(name: name)
            print(manager.migrationCreatedMessages())
        } catch {
            print("Error: \(error)")
        }
        await spectro.shutdown()
    }
}
