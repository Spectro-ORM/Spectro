import Foundation
import Testing
@testable import Spectro

/// Shared test infrastructure for integration tests that need a live PostgreSQL connection.
///
/// Uses a single `Spectro` instance for the lifetime of the test process, created
/// on first access, to avoid repeated pool startup between tests. Tests that own
/// a separate instance must shut it down. Any crash is a test failure.
///
/// Connect to `localhost:5432` with user/password `postgres/postgres` and database
/// `spectro_test`. Create the database manually before running tests:
///
///     createdb -U postgres spectro_test
///
struct TestDatabase {
    static let hostname = ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost"
    static let port = Int(ProcessInfo.processInfo.environment["DB_PORT"] ?? "5432") ?? 5432
    static let username = ProcessInfo.processInfo.environment["DB_USER"] ?? "postgres"
    static let password = ProcessInfo.processInfo.environment["DB_PASSWORD"] ?? "postgres"
    static let database = ProcessInfo.processInfo.environment["TEST_DB_NAME"] ?? "spectro_test"

    /// Create a fresh Spectro instance. For most integration tests, prefer `sharedRepo()`
    /// to avoid EventLoopGroup churn. Use this only when you need a connection with a
    /// specific configuration, or when you'll call `shutdown()` yourself.
    static func makeSpectro() throws -> Spectro {
        let config = DatabaseConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            maxConnectionsPerEventLoop: 1,
            numberOfThreads: 1
        )
        return try Spectro(configuration: config)
    }

    /// Shared actor that owns a single long-lived Spectro instance for the test run.
    private actor SharedDB {
        private var _spectro: Spectro?

        func spectro() throws -> Spectro {
            if let s = _spectro { return s }
            let s = try TestDatabase.makeSpectro()
            _spectro = s
            return s
        }
    }

    private static let _shared = SharedDB()

    /// Returns a `GenericDatabaseRepo` backed by the single shared connection pool.
    /// Thread-safe: the underlying actor serializes initialization.
    static func sharedRepo() async throws -> GenericDatabaseRepo {
        try await _shared.spectro().repository()
    }
}
