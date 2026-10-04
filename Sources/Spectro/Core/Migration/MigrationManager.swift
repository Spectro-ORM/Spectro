import Foundation
import SpectroCommon

/// Backward-compatible SQL-file migration facade.
public final class MigrationManager: Sendable {
    private let runner: MigrationRunner
    private let migrationsPath: URL
    internal static let lockKey = MigrationRunner.lockKey

    public init(connection: DatabaseConnection, migrationsPath: URL? = nil, lockTimeout: Duration = .seconds(30)) {
        self.migrationsPath = migrationsPath ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Migrations")
        self.runner = MigrationRunner(connection: connection, legacyDirectory: self.migrationsPath, lockTimeout: lockTimeout)
    }

    public func ensureMigrationTableExists() async throws { try await runner.ensureMigrationTableExists() }
    public func getMigrationStatus() async throws -> [MigrationRecord] { try await runner.getMigrationStatus() }
    public func discoverMigrations() throws -> [MigrationFile] { try MigrationCatalog.discoverFiles(in: migrationsPath) }

    public func getMigrationStatuses() async throws -> (discovered: [MigrationFile], statuses: [String: MigrationStatus]) {
        let discovered = try discoverMigrations()
        let applied = try await getMigrationStatus()
        return (discovered, Dictionary(uniqueKeysWithValues: applied.map { ($0.version, $0.status) }))
    }

    public func getPendingMigrations() async throws -> [MigrationFile] {
        let (discovered, statuses) = try await getMigrationStatuses()
        return discovered.filter { statuses[$0.version] == nil || statuses[$0.version] == .pending }
    }

    public func getAppliedMigrations() async throws -> [MigrationFile] {
        let (discovered, statuses) = try await getMigrationStatuses()
        return discovered.filter { statuses[$0.version] == .completed }
    }

    public func runMigrations() async throws { try await runner.runMigrations() }
    public func runRollback(steps: Int? = nil) async throws { try await runner.runRollback(steps: steps) }
    public func insertMigrationRecord(_ record: MigrationRecord) async throws { try await runner.insertMigrationRecord(record) }
}
