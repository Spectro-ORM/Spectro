import ArgumentParser
import NIOCore
import PostgresKit
@preconcurrency import Spectro
import SpectroCommon

struct Drop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "drop", abstract: "Drop an existing database")

    @Argument(help: "Name of the database to drop")
    var name: String?

    @Option(name: .long, help: "Database Username") var username: String?
    @Option(name: .long, help: "Database Password") var password: String?
    @Option(name: .long, help: "Database Name (alternative to positional argument)") var database: String?

    func run() async throws {
        let dbName = name ?? database
        guard let dbName, !dbName.isEmpty else {
            print("Error: Database name is required.")
            print("Usage: spectro database drop <name>")
            print("   or: spectro database drop --database <name>")
            throw ExitCode.validationFailure
        }

        guard dbName != "postgres" else {
            print("Error: Refusing to drop 'postgres' — that's the system database.")
            throw ExitCode.validationFailure
        }

        try validateDatabaseIdentifier(dbName)

        try await ConfigurationManager.shared.loadEnvFile()
        var overrides: [String: String] = [:]
        if let v = username { overrides["username"] = v }
        if let v = password { overrides["password"] = v }

        let config = await ConfigurationManager.shared.getDatabaseConfig(overrides: overrides)
        let spectro = try Spectro(
            hostname: config.hostname, port: config.port,
            username: config.username, password: config.password, database: "postgres"
        )

        let repo = spectro.repository()
        do {
            // Disconnect other sessions before dropping (parameterized)
            let _ = try await repo.executeRawQuery(
                sql: "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
                parameters: [PostgresData(string: dbName)]
            )
            try await repo.executeRawSQL("DROP DATABASE \"\(escapeIdentifier(dbName))\"")
            print("Database '\(dbName)' dropped successfully.")
        } catch {
            await spectro.shutdown()
            let message = String(describing: error)
            if message.contains("does not exist") {
                print("Database '\(dbName)' does not exist.")
                return
            }
            print("Error: Could not drop database '\(dbName)'.")
            print("Reason: \(extractPGMessage(from: error))")
            throw ExitCode.failure
        }
        await spectro.shutdown()
    }
}
