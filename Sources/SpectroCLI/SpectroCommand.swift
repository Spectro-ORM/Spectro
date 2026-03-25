import ArgumentParser

@main
struct SpectroCommand: AsyncParsableCommand {
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
        subcommands: [Migrate.self, Rollback.self, Status.self]
    )
}

struct GenerateGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate project files",
        subcommands: [GenerateMigration.self]
    )
}
