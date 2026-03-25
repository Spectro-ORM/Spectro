import Foundation
import Testing
@testable import Spectro

/// Shared test infrastructure for integration tests that need a live PostgreSQL connection.
///
/// Connects to `localhost:5432` with user/password `postgres/postgres` and database `spectro_test`.
/// Create the database manually before running tests:
///
///     createdb -U postgres spectro_test
///
struct TestDatabase {
    static let hostname = ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost"
    static let port = Int(ProcessInfo.processInfo.environment["DB_PORT"] ?? "5432") ?? 5432
    static let username = ProcessInfo.processInfo.environment["DB_USER"] ?? "postgres"
    static let password = ProcessInfo.processInfo.environment["DB_PASSWORD"] ?? "postgres"
    static let database = ProcessInfo.processInfo.environment["TEST_DB_NAME"] ?? "spectro_test"

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
}
