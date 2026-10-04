import ArgumentParser
import Foundation

struct InitializeMigrations: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "init", abstract: "Scaffold a project's Swift migration executable.")
    @Option(name: .long) var target: String

    func run() throws {
        try MigrationProject.validateTypeName(target)
        guard let root = MigrationProject.packageRoot() else { throw ValidationError("Run this command inside a Swift package.") }
        let source = try MigrationProject.containedPath("Sources/\(target)", root: root)
        let descriptor = root.appendingPathComponent(".spectro.json")
        // Check every destination before creating any files.
        for destination in [descriptor, source] {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw ValidationError("Refusing to overwrite \(destination.path).")
            }
        }
        let entry = """
            import SpectroMigrations

            @main
            struct MigrationMain {
                static func main() async {
                    await MigrationCommand.main(migrations: migrations)
                }
            }

            """
        let registry = """
            import SpectroMigrations

            let migrations = MigrationRegistry {
                // Register migrations here, for example: CreateUsers()
            }

            """
        let config = MigrationProject.Descriptor(formatVersion: 1,
            migrations: .init(product: target, sourceDirectory: "Sources/\(target)"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Migrations"), withIntermediateDirectories: true)
        try Data(entry.utf8).write(to: source.appendingPathComponent("EntryPoint.swift"), options: .withoutOverwriting)
        try Data(registry.utf8).write(to: source.appendingPathComponent("Migrations.swift"), options: .withoutOverwriting)
        try data.write(to: descriptor, options: .withoutOverwriting)
        print("""
            Created .spectro.json and Sources/\(target).

            Add this target to Package.swift before running migrations (use your Spectro dependency's package identity):
            .executableTarget(
                name: "\(target)",
                dependencies: [.product(name: "SpectroMigrations", package: "Spectro")]
            )

            To package existing SQL, place unchanged files in Sources/\(target)/LegacySQL,
            add resources: [.copy("LegacySQL")] to the target, and register:
            SQLMigrations(bundle: .module, directory: "LegacySQL")
            """)
    }
}

struct PlanMigrations: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "plan", abstract: "Preview the configured project's migrations offline.")
    @Option(name: .long) var migration: String?
    @Option(name: .long) var direction: String = "up"
    func run() throws {
        throw ValidationError("No Swift migrations configured in this package. Run spectro migrate init --target AppMigrations.")
    }
}

