import Foundation
@preconcurrency import PostgresKit
import SpectroCommon

// All stored properties are immutable, so @Sendable closure capture is safe.
public final class MigrationManager: @unchecked Sendable {
    private let connection: DatabaseConnection
    private let migrationsPath: URL

    private let lockTimeout: Duration
    // Stable across processes and releases. PostgreSQL scopes advisory locks to a database.
    internal static let lockKey: Int = 0x5350454354524F

    public init(connection: DatabaseConnection, migrationsPath: URL? = nil, lockTimeout: Duration = .seconds(30)) {
        self.connection = connection
        self.lockTimeout = lockTimeout
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.migrationsPath = migrationsPath
            ?? currentDirectory.appendingPathComponent("Sources/Migrations")
    }

    public func ensureMigrationTableExists() async throws {
        try await withLockedSession { session in
            try await self.ensureMigrationTableExists(using: session)
        }
    }

    private func ensureMigrationTableExists(using session: TransactionContext) async throws {
        let createEnumSql = """
            DO $$ BEGIN
                CREATE TYPE migration_status AS ENUM ('pending', 'completed', 'failed');
            EXCEPTION WHEN duplicate_object THEN null; END $$;
            """
        try await session.execute(createEnumSql)

        let createTableSql = """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                status migration_status NOT NULL DEFAULT 'pending'
            );
            """
        try await session.execute(createTableSql)
    }

    public func getMigrationStatus() async throws -> [MigrationRecord] {
        try await getMigrationStatus(using: connection)
    }

    private func getMigrationStatus(using executor: any QueryExecutor) async throws -> [MigrationRecord] {
        // Inspecting status must not require DDL privileges, including on a fresh database.
        let exists = try await executor.executeQuery(
            sql: "SELECT to_regclass('schema_migrations') IS NOT NULL AS present",
            parameters: [],
            resultMapper: { $0.makeRandomAccess()[data: "present"].bool ?? false }
        ).first ?? false
        guard exists else { return [] }

        let sql = """
            SELECT version, name, applied_at, status
            FROM schema_migrations
            ORDER BY version ASC
            """
        return try await executor.executeQuery(sql: sql, parameters: []) { row in
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

    /// Apply pending migrations under a database-wide session lock. Each migration
    /// and its tracking record commit together in a separate transaction.
    public func runMigrations() async throws {
        try await withLockedSession { session in
            try await self.ensureMigrationTableExists(using: session)
            let records = try await self.getMigrationStatus(using: session)
            let statuses = Dictionary(uniqueKeysWithValues: records.map { ($0.version, $0.status) })
            let pending = try self.discoverMigrations().filter {
                statuses[$0.version] == nil || statuses[$0.version] == .pending
            }
            for migration in pending {
                let content = try self.loadMigrationContent(from: migration)
                try await self.apply(migration, sql: content.up, status: .completed, using: session)
            }
        }
    }

    public func runRollback(steps: Int? = nil) async throws {
        guard steps == nil || steps! >= 0 else {
            throw SpectroError.invalidParameter(name: "steps", value: String(steps!), reason: "Must be nonnegative")
        }
        try await withLockedSession { session in
            try await self.ensureMigrationTableExists(using: session)
            let records = try await self.getMigrationStatus(using: session)
            let completed = Set(records.filter { $0.status == .completed }.map(\.version))
            let applied = try self.discoverMigrations().filter { completed.contains($0.version) }
            for migration in applied.suffix(steps ?? applied.count).reversed() {
                let content = try self.loadMigrationContent(from: migration)
                try await self.apply(migration, sql: content.down, status: .pending, using: session)
            }
        }
    }

    public func insertMigrationRecord(_ record: MigrationRecord) async throws {
        try await withLockedSession { session in
            try await self.ensureMigrationTableExists(using: session)
            try await session.execute("""
                INSERT INTO schema_migrations (version, name, status)
                VALUES ($1, $2, $3::migration_status)
                ON CONFLICT (version) DO NOTHING;
                """, [
                    PostgresData(string: record.version),
                    PostgresData(string: record.name),
                    PostgresData(string: record.status.rawValue)
                ])
        }
    }

    // MARK: - Private

    private func withLockedSession<T: Sendable>(
        _ work: @Sendable (TransactionContext) async throws -> T
    ) async throws -> T {
        guard lockTimeout >= .zero else {
            throw SpectroError.invalidParameter(name: "lockTimeout", value: "\(lockTimeout)", reason: "Must be nonnegative")
        }
        return try await connection.withMigrationSession { session in
            // PostgreSQL 14+ can notice a closed client during long-running SQL,
            // rather than retaining its transaction and locks until SQL finishes.
            // This setting is confined to the disposable migration session.
            try await session.execute("""
                SELECT set_config(name, '100ms', false) FROM pg_settings
                WHERE name = 'client_connection_check_interval'
                """)
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: self.lockTimeout)
            while true {
                try Task.checkCancellation()
                let acquired = try await session.query(
                    "SELECT pg_try_advisory_lock($1::bigint) AS acquired", [.init(int: Self.lockKey)]
                ) { $0.makeRandomAccess()[data: "acquired"].bool == true }.first == true
                if acquired { break }
                guard clock.now < deadline else { throw MigrationError.lockTimeout }
                try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(50))))
            }
            // DatabaseConnection closes the reserved session on every exit path.
            return try await work(session)
        }
    }

    private func apply(
        _ migration: MigrationFile, sql: String, status: MigrationStatus, using session: TransactionContext
    ) async throws {
        let statements = try SQLStatementParser.parse(sql)
        try Task.checkCancellation()
        try await session.execute("BEGIN ISOLATION LEVEL READ COMMITTED")
        do {
            for statement in statements {
                try Task.checkCancellation()
                try await session.execute(statement)
            }
            try await updateMigrationStatus(migration, status: status, using: session)
            try Task.checkCancellation()
            try await session.execute("COMMIT")
        } catch {
            if Task.isCancelled { throw CancellationError() }
            do { try await session.execute("ROLLBACK") }
            catch let rollbackError {
                throw SpectroError.transactionAndRollbackFailed(original: error, rollback: rollbackError)
            }
            throw SpectroError.transactionFailed(underlying: error)
        }
    }

    private func updateMigrationStatus(
        _ migration: MigrationFile, status: MigrationStatus, using transaction: TransactionContext
    ) async throws {
        let sql = """
            INSERT INTO schema_migrations (version, name, status)
            VALUES ($1, $2, $3::migration_status)
            ON CONFLICT(version)
              DO UPDATE SET status=$3::migration_status, applied_at=CURRENT_TIMESTAMP;
            """
        try await transaction.execute(sql, [
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
        guard let downMarkerRange = text.range(of: Self.downMarker),
              upMarkerRange.upperBound <= downMarkerRange.lowerBound else {
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

}
