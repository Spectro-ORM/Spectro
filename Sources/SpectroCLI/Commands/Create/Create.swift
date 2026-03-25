import ArgumentParser
import NIOCore
import PostgresKit
@preconcurrency import Spectro
import SpectroCommon

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new database")

    @Argument(help: "Name of the database to create")
    var name: String?

    @Option(name: .long, help: "Database Username") var username: String?
    @Option(name: .long, help: "Database Password") var password: String?
    @Option(name: .long, help: "Database Name (alternative to positional argument)") var database: String?

    func run() async throws {
        let dbName = name ?? database
        guard let dbName, !dbName.isEmpty else {
            print("Error: Database name is required.")
            print("Usage: spectro database create <name>")
            print("   or: spectro database create --database <name>")
            throw ExitCode.validationFailure
        }

        guard dbName != "postgres" else {
            print("Error: Refusing to create 'postgres' — that's the system database.")
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
            try await repo.executeRawSQL("CREATE DATABASE \"\(escapeIdentifier(dbName))\"")
            print("Database '\(dbName)' created successfully.")
        } catch {
            await spectro.shutdown()
            let message = String(describing: error)
            if message.contains("already exists") {
                print("Database '\(dbName)' already exists.")
                return
            }
            print("Error: Could not create database '\(dbName)'.")
            print("Reason: \(extractPGMessage(from: error))")
            throw ExitCode.failure
        }
        await spectro.shutdown()
    }
}
