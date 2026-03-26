import ArgumentParser
import NIOCore
@preconcurrency import Noora
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
            SpectroUI.noora.error(.alert(
                "Database name is required.",
                takeaways: [
                    "Usage: \(.command("spectro database create <name>"))",
                    "   or: \(.command("spectro database create --database <name>"))",
                ]
            ))
            throw ExitCode.validationFailure
        }

        guard dbName != "postgres" else {
            SpectroUI.noora.error(.alert("Refusing to create \(.danger("postgres")) — that's the system database."))
            throw ExitCode.validationFailure
        }

        do {
            try validateDatabaseIdentifier(dbName)
        } catch {
            SpectroUI.noora.error(.alert("\(error.localizedDescription)"))
            throw ExitCode.validationFailure
        }

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
            try await SpectroUI.noora.progressStep(
                message: "Creating database '\(dbName)'",
                successMessage: "Database '\(dbName)' created successfully.",
                errorMessage: "Failed to create database '\(dbName)'",
                showSpinner: true
            ) { _ in
                try await repo.executeRawSQL("CREATE DATABASE \"\(escapeIdentifier(dbName))\"")
            }
        } catch {
            await spectro.shutdown()
            let message = String(describing: error)
            if message.contains("already exists") {
                SpectroUI.noora.warning(.alert(
                    "Database \(.primary(dbName)) already exists.",
                    takeaway: "Use \(.command("spectro migrate status")) to check current state"
                ))
                return
            }
            SpectroUI.noora.error(.alert(
                "Could not create database \(.primary(dbName)).",
                takeaways: ["\(.muted(extractPGMessage(from: error)))"]
            ))
            throw ExitCode.failure
        }
        await spectro.shutdown()
    }
}
