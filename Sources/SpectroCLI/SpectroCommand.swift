import ArgumentParser
import Foundation

@main
struct SpectroCommand: AsyncParsableCommand {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            if arguments.count >= 2, arguments[0] == "migrate",
               ["up", "down", "status", "plan"].contains(arguments[1]),
               let project = try MigrationProject.discover() {
                let status = try await MigrationProjectLauncher.run(project: project, arguments: Array(arguments.dropFirst()))
                exit(withError: ExitCode(rawValue: status))
            }
        } catch { exit(withError: error) }
        await main(nil)
    }
    static let configuration = CommandConfiguration(
        commandName: "spectro",
        abstract: "Spectro CLI — database migrations and management",
        subcommands: [
            DatabaseGroup.self,
            MigrateGroup.self,
            GenerateGroup.self,
            Test.self,
        ]
    )
}

struct DatabaseGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "database",
        abstract: "Database management commands",
        subcommands: [Create.self, Drop.self]
    )
}

struct MigrateGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Run and manage migrations",
        subcommands: [Migrate.self, Rollback.self, Status.self, InitializeMigrations.self, PlanMigrations.self]
    )
}

struct GenerateGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate project files",
        subcommands: [GenerateMigration.self]
    )
}
