import ArgumentParser
import NIOCore
@preconcurrency import Noora
import Spectro
import SpectroCommon

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Display status of all migrations"
    )

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
            let (migrations, statuses) = try await manager.getMigrationStatuses()

            guard !migrations.isEmpty else {
                SpectroUI.noora.info(.alert(
                    "No migrations found.",
                    takeaways: [
                        "Run \(.command("spectro generate migration <name>")) to create one",
                        "Run \(.command("spectro migrate up")) to apply migrations",
                    ]
                ))
                await spectro.shutdown()
                return
            }

            let headers: [TableCellStyle] = [
                .primary("Version"),
                .primary("Name"),
                .primary("Status"),
            ]

            let rows: [StyledTableRow] = migrations.map { m in
                let status = statuses[m.version] ?? .pending
                let statusCell: TableCellStyle = switch status {
                case .completed: .success(status.rawValue.capitalized)
                case .pending:   .warning(status.rawValue.capitalized)
                case .failed:    .danger(status.rawValue.capitalized)
                }
                return [
                    .plain(m.version),
                    .plain(m.name),
                    statusCell,
                ]
            }

            SpectroUI.noora.table(headers: headers, rows: rows)

            var pending = 0, completed = 0, failed = 0
            for m in migrations {
                switch statuses[m.version] {
                case nil, .pending: pending += 1
                case .completed:    completed += 1
                case .failed:       failed += 1
                }
            }

            SpectroUI.noora.info(.alert(
                "\(migrations.count) total: \(.success("\(completed) applied")), \(.accent("\(pending) pending")), \(.danger("\(failed) failed"))"
            ))
        } catch {
            SpectroUI.noora.error(.alert(
                "Failed to check migration status",
                takeaways: ["\(.muted(error.localizedDescription))"]
            ))
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }
}
