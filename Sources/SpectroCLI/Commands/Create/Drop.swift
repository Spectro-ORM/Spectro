import ArgumentParser
import NIOCore
@preconcurrency import Noora
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
    @Flag(name: .long, help: "Skip confirmation prompt") var force: Bool = false

    func run() async throws {
        let dbName = name ?? database
        guard let dbName, !dbName.isEmpty else {
            SpectroUI.noora.error(.alert(
                "Database name is required.",
                takeaways: [
                    "Usage: \(.command("spectro database drop <name>"))",
                    "   or: \(.command("spectro database drop --database <name>"))",
                ]
            ))
            throw ExitCode.validationFailure
        }

        guard dbName != "postgres" else {
            SpectroUI.noora.error(.alert("Refusing to drop \(.danger("postgres")) — that's the system database."))
            throw ExitCode.validationFailure
        }

        do {
            try validateDatabaseIdentifier(dbName)
        } catch {
            SpectroUI.noora.error(.alert("\(error.localizedDescription)"))
            throw ExitCode.validationFailure
        }

        if !force {
            let confirmed = SpectroUI.noora.yesOrNoChoicePrompt(
                title: "Database",
                question: "Drop database \(.danger(dbName))? This cannot be undone.",
                defaultAnswer: false
            )
            guard confirmed else {
                SpectroUI.noora.info(.alert(
                    "Drop cancelled.",
                    takeaways: ["Database \(.primary(dbName)) was not modified"]
                ))
                return
            }
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
                message: "Dropping database '\(dbName)'",
                successMessage: "Database '\(dbName)' dropped successfully.",
                errorMessage: "Failed to drop database '\(dbName)'",
                showSpinner: true
            ) { _ in
                let _ = try await repo.executeRawQuery(
                    sql: "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
                    parameters: [PostgresData(string: dbName)]
                )
                try await repo.executeRawSQL("DROP DATABASE \"\(escapeIdentifier(dbName))\"")
            }
        } catch {
            await spectro.shutdown()
            let message = String(describing: error)
            if message.contains("does not exist") {
                SpectroUI.noora.warning(.alert(
                    "Database \(.primary(dbName)) does not exist.",
                    takeaway: "Use \(.command("spectro database create \(dbName)")) to create it"
                ))
                return
            }
            SpectroUI.noora.error(.alert(
                "Could not drop database \(.primary(dbName)).",
                takeaways: ["\(.muted(extractPGMessage(from: error)))"]
            ))
            throw ExitCode.failure
        }
        await spectro.shutdown()
    }
}
