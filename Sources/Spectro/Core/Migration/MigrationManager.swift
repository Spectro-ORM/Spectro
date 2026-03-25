import Foundation
@preconcurrency import PostgresKit
import SpectroCommon

// Both stored properties are immutable (`let`), so @Sendable closure capture is safe.
public final class MigrationManager: @unchecked Sendable {
    private let connection: DatabaseConnection
    private let migrationsPath: URL

    public init(connection: DatabaseConnection, migrationsPath: URL? = nil) {
        self.connection = connection
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.migrationsPath = migrationsPath
            ?? currentDirectory.appendingPathComponent("Sources/Migrations")
    }

    public func ensureMigrationTableExists() async throws {
        let createEnumSql = """
            DO $$ BEGIN
                CREATE TYPE migration_status AS ENUM ('pending', 'completed', 'failed');
            EXCEPTION WHEN duplicate_object THEN null; END $$;
            """
        try await connection.executeUpdate(sql: createEnumSql)

        let createTableSql = """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                status migration_status NOT NULL DEFAULT 'pending'
            );
            """
        try await connection.executeUpdate(sql: createTableSql)
    }

    public func getMigrationStatus() async throws -> [MigrationRecord] {
        let sql = """
            SELECT version, name, applied_at, status
            FROM schema_migrations
            ORDER BY version ASC
            """
        return try await connection.executeQuery(sql: sql) { row in
            let r = row.makeRandomAccess()
            guard let version = r[data: "version"].string else {
                throw SpectroError.resultDecodingFailed(column: "version", expectedType: "String")
            }
            guard let name = r[data: "name"].string else {
                throw SpectroError.resultDecodingFailed(column: "name", expectedType: "String")
            }
            guard let appliedAt = r[data: "applied_at"].date else {
                throw SpectroError.resultDecodingFailed(column: "applied_at", expectedType: "Date")
            }
            guard let statusString = r[data: "status"].string else {
                throw SpectroError.resultDecodingFailed(column: "status", expectedType: "String")
            }
            return MigrationRecord(
                version: version,
                name: name,
                appliedAt: appliedAt,
                status: MigrationStatus(rawValue: statusString) ?? .pending
            )
        }
    }

    public func discoverMigrations() throws -> [MigrationFile] {
        guard FileManager.default.fileExists(atPath: migrationsPath.path) else {
            throw MigrationError.directoryNotFound(migrationsPath.path)
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: migrationsPath, includingPropertiesForKeys: nil
        )
        return files.filter { $0.pathExtension == "sql" }
            .compactMap { url -> MigrationFile? in
                let name = url.deletingPathExtension().lastPathComponent
                let parts = name.split(separator: "_", maxSplits: 1)
                guard parts.count == 2,
                      let ts = Double(parts[0]), ts > 0,
                      ts < Date().timeIntervalSince1970 + 100 * 365 * 24 * 60 * 60
                else { return nil }
                return MigrationFile(
                    version: "\(parts[0])_\(parts[1])",
                    name: String(parts[1]),
                    filePath: url
                )
            }
            .sorted { $0.version < $1.version }
    }

    public func getMigrationStatuses() async throws -> (
        discovered: [MigrationFile], statuses: [String: MigrationStatus]
    ) {
        let discovered = try discoverMigrations()
        let applied = try await getMigrationStatus()
        let statusMap = Dictionary(uniqueKeysWithValues: applied.map { ($0.version, $0.status) })
        return (discovered, statusMap)
    }

    public func getPendingMigrations() async throws -> [MigrationFile] {
        let (discovered, statuses) = try await getMigrationStatuses()
        return discovered.filter { statuses[$0.version] == nil || statuses[$0.version] == .pending }
    }

    public func getAppliedMigrations() async throws -> [MigrationFile] {
        let (discovered, statuses) = try await getMigrationStatuses()
        return discovered.filter { statuses[$0.version] == .completed }
    }

    public func runMigrations() async throws {
        try await ensureMigrationTableExists()
        let pending = try await getPendingMigrations()
        for migration in pending {
            let content = try loadMigrationContent(from: migration)
            try await withTransaction { db in
                let stmts = try SQLStatementParser.parse(content.up)
                for stmt in stmts { try await db.executeUpdate(sql: stmt) }
                return ()
            }
            try await updateMigrationStatus(migration, status: .completed)
        }
    }

    public func runRollback(steps: Int? = nil) async throws {
        try await ensureMigrationTableExists()
        let applied = try await getAppliedMigrations()
        let toRollback = Array(applied.suffix(steps ?? applied.count).reversed())
        for migration in toRollback {
            let content = try loadMigrationContent(from: migration)
            try await withTransaction { db in
                let stmts = try SQLStatementParser.parse(content.down)
                for stmt in stmts { try await db.executeUpdate(sql: stmt) }
                return ()
            }
            try await updateMigrationStatus(migration, status: .pending)
        }
    }

    public func insertMigrationRecord(_ record: MigrationRecord) async throws {
        try await ensureMigrationTableExists()
        let sql = """
            INSERT INTO schema_migrations (version, name, status)
            VALUES ($1, $2, $3::migration_status)
            ON CONFLICT (version) DO NOTHING;
            """
        try await connection.executeUpdate(sql: sql, parameters: [
            PostgresData(string: record.version),
            PostgresData(string: record.name),
            PostgresData(string: record.status.rawValue)
        ])
    }

    public func getFormattedStatus() async throws -> String {
        let (migrations, statuses) = try await getMigrationStatuses()
        guard !migrations.isEmpty else { return formatEmptyStateMessage() }

        let green = "\u{001B}[32m", yellow = "\u{001B}[33m"
        let red = "\u{001B}[31m", reset = "\u{001B}[0m", dim = "\u{001B}[2m"

        var lines = ["\nMigration Status:", "Location: \(migrationsPath.path)",
                     String(repeating: "-", count: 80),
                     "Version".padding(toLength: 40, withPad: " ", startingAt: 0)
                       + "Name".padding(toLength: 20, withPad: " ", startingAt: 0) + "Status",
                     String(repeating: "-", count: 80)]

        for m in migrations {
            let status = statuses[m.version] ?? .pending
            let color = status == .completed ? green : status == .pending ? yellow : red
            lines.append(
                m.version.padding(toLength: 40, withPad: " ", startingAt: 0)
                + m.name.padding(toLength: 20, withPad: " ", startingAt: 0)
                + color + status.rawValue.capitalized + reset
            )
        }

        var pending = 0, completed = 0, failed = 0
        for m in migrations {
            switch statuses[m.version] {
            case nil, .pending: pending += 1
            case .completed:    completed += 1
            case .failed:       failed += 1
            }
        }

        lines += ["", "Summary:", "Total: \(migrations.count)",
                  "Pending: \(pending > 0 ? yellow : green)\(pending)\(reset)",
                  "Completed: \(green)\(completed)\(reset)",
                  "Failed: \(failed > 0 ? red : green)\(failed)\(reset)",
                  "", dim + "Run 'spectro migration --help' for commands" + reset, ""]

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func withTransaction<T: Sendable>(
        _ operation: @Sendable @escaping (DatabaseConnection) async throws -> T
    ) async throws -> T {
        try await connection.transaction { [connection] _ in
            try await operation(connection)
        }
    }

    private func updateMigrationStatus(_ migration: MigrationFile, status: MigrationStatus) async throws {
        let sql = """
            INSERT INTO schema_migrations (version, name, status)
            VALUES ($1, $2, $3::migration_status)
            ON CONFLICT(version)
              DO UPDATE SET status=$3::migration_status, applied_at=CURRENT_TIMESTAMP;
            """
        try await connection.executeUpdate(sql: sql, parameters: [
            PostgresData(string: migration.version),
            PostgresData(string: migration.name),
            PostgresData(string: status.rawValue)
        ])
    }

    /// Parse `-- migrate:up` and `-- migrate:down` sections from a `.sql` migration file.
    ///
    /// File format:
    /// ```sql
    /// -- migrate:up
    /// CREATE TABLE "users" (...);
    ///
    /// -- migrate:down
    /// DROP TABLE "users";
    /// ```
    private func loadMigrationContent(from file: MigrationFile) throws -> (up: String, down: String) {
        let text = try String(contentsOf: file.filePath, encoding: .utf8)

        guard let upMarkerRange = text.range(of: Self.upMarker) else {
            throw MigrationError.invalidMigrationFile(file.version)
        }
        guard let downMarkerRange = text.range(of: Self.downMarker) else {
            throw MigrationError.invalidMigrationFile(file.version)
        }

        // up section: content between the two markers
        let upSQL = text[upMarkerRange.upperBound..<downMarkerRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // down section: everything after the down marker
        let downSQL = text[downMarkerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !upSQL.isEmpty else { throw MigrationError.invalidMigrationFile(file.version) }

        return (up: upSQL, down: downSQL)
    }

    private static let upMarker = "-- migrate:up"
    private static let downMarker = "-- migrate:down"

    // MARK: - CLI Message Helpers

    private static let migrationCreatedMessageOptions = [
        "📜 Fresh migration dropped.", "✨ New migration, who dis?",
        "🚀 New migration ready for takeoff!", "🎉 Migration created!"
    ]

    private static let migrationAppliedMessageOptions = [
        "✅ Migration applied!", "🚀 Migration complete. All systems go!",
        "🎉 Migration applied successfully.", "✨ Smooth — migration applied."
    ]

    private static let rollbackAppliedMessageOptions = [
        "🔄 Rollback complete.", "⏪ Rolled back successfully.",
        "🛠️ Rollback done.", "🔙 Rollback complete."
    ]

    public func migrationCreatedMessages() -> String {
        Self.migrationCreatedMessageOptions.randomElement()!
    }

    public func migrationAppliedMessages() -> String {
        Self.migrationAppliedMessageOptions.randomElement()!
    }

    public func rollbackAppliedMessages() -> String {
        Self.rollbackAppliedMessageOptions.randomElement()!
    }

    private func formatEmptyStateMessage() -> String {
        """
        Migration Status:
        No migrations found in \(migrationsPath.path).

        Quick Start:
          spectro migrate generate <name>
          spectro migrate up
        """
    }
}
