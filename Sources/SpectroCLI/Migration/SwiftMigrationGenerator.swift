import ArgumentParser
import Foundation

enum SwiftMigrationGenerator {
    static func generate(name: String, project: MigrationProject) throws {
        try MigrationProject.validateTypeName(name)
        let directory = try MigrationProject.containedPath(
            project.sourceDirectory.path.dropFirst(project.root.path.count + 1).description + "/Migrations",
            root: project.root)
        let file = directory.appendingPathComponent(name + ".swift")
        guard !FileManager.default.fileExists(atPath: file.path) else {
            throw ValidationError("Refusing to overwrite \(file.lastPathComponent).")
        }
        let snake = name
            .replacingOccurrences(of: #"([A-Z]+)([A-Z][a-z])"#, with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1_$2", options: .regularExpression)
            .lowercased()
        let id = "\(Int(Date().timeIntervalSince1970))_\(snake)"
        let source = """
            import SpectroMigrations

            struct \(name): Migration {
                static let id = "\(id)"

                var change: MigrationPlan {
                    get {
                        // Add operations here before registering this migration.
                    }
                }
            }

            """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: file, options: .withoutOverwriting)
        print("Created \(file.path)")
        print("Add \(name)() inside MigrationRegistry in Migrations.swift.")
    }
}
