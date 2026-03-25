import Foundation
import Spectro
import SpectroCommon

public struct MigrationGenerator {
    private let fileManager: FileManager = .default
    private let migrationManager: MigrationManager

    public init(migrationManager: MigrationManager) {
        self.migrationManager = migrationManager
    }

    public func generate(name: String) async throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let migrationName = name.snakeCase()
        let fileName = "\(timestamp)_\(migrationName).sql"

        // SQL migration file with standard up/down section markers
        let content = """
            -- Spectro Migration
            -- Version: \(timestamp)_\(migrationName)
            -- Generated: \(ISO8601DateFormatter().string(from: Date()))

            -- migrate:up

            -- TODO: write your forward migration SQL here
            -- Example:
            -- CREATE TABLE IF NOT EXISTS "my_table" (
            --     "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            --     "name" TEXT NOT NULL DEFAULT '',
            --     "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            -- );

            -- migrate:down

            -- TODO: write your rollback SQL here
            -- Example:
            -- DROP TABLE IF EXISTS "my_table";
            """

        let migrationsPath = "Sources/Migrations"
        try fileManager.createDirectory(
            atPath: migrationsPath,
            withIntermediateDirectories: true
        )

        let filePath = "\(migrationsPath)/\(fileName)"
        guard !fileManager.fileExists(atPath: filePath) else {
            throw MigrationError.fileExists(filePath)
        }

        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        let record = MigrationRecord(
            version: "\(timestamp)_\(migrationName)",
            name: migrationName,
            appliedAt: Date(),
            status: .pending
        )
        try await migrationManager.insertMigrationRecord(record)
    }
}
