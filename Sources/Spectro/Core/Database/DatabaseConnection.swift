// @preconcurrency suppresses Sendable warnings originating in NIO/PostgresKit types
// that predate Swift 6. Remove when those packages gain full Sendable annotations.
@preconcurrency import NIOCore
@preconcurrency import PostgresKit
import Foundation
import NIOSSL

public actor DatabaseConnection {
    // nonisolated(unsafe) lets us call pools.shutdown() — which is marked
    // @available(*, noasync) — from within the async shutdown() method without
    // hitting the "calls wait()" diagnostic. Both are `let` constants so there
    // is no concurrent mutation to guard against.
    private nonisolated(unsafe) let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>
    private nonisolated let eventLoopGroup: any EventLoopGroup
    private let configuration: DatabaseConfiguration
    private var isShutdown = false

    /// Tracks the number of in-flight query operations. shutdown() waits for
    /// this to reach zero before tearing down the pool, preventing SIGBUS
    /// crashes caused by NIO future callbacks accessing a freed pool.
    private var activeOperations = 0
    private var shutdownContinuation: CheckedContinuation<Void, Never>?

    public init(configuration: DatabaseConfiguration) throws {
        self.configuration = configuration
        let sqlConfig = SQLPostgresConfiguration(
            hostname: configuration.hostname,
            port: configuration.port,
            username: configuration.username,
            password: configuration.password,
            database: configuration.database,
            tls: try configuration.tlsConfiguration.map { .require(try NIOSSLContext(configuration: $0)) } ?? .disable
        )

        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: configuration.numberOfThreads)
        let source = PostgresConnectionSource(sqlConfiguration: sqlConfig)

        self.pools = EventLoopGroupConnectionPool(
            source: source,
            maxConnectionsPerEventLoop: configuration.maxConnectionsPerEventLoop,
            on: eventLoopGroup
        )
    }

    // MARK: - Operation Tracking

    private func beginOperation() throws {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }
        activeOperations += 1
    }

    private func endOperation() {
        activeOperations -= 1
        if activeOperations == 0, let continuation = shutdownContinuation {
            shutdownContinuation = nil
            continuation.resume()
        }
    }

    // MARK: - Query Execution

    public func executeQuery<T: Sendable>(
        sql: String,
        parameters: [PostgresData] = [],
        resultMapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T] {
        try beginOperation()

        do {
            let result: [T] = try await withCheckedThrowingContinuation { continuation in
                let future: EventLoopFuture<[T]> = self.pools.withConnection { connection in
                    connection.query(sql, parameters).flatMapThrowing { result in
                        try result.rows.map(resultMapper)
                    }
                }
                future.whenComplete { result in
                    switch result {
                    case .success(let rows): continuation.resume(returning: rows)
                    case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                    }
                }
            }
            endOperation()
            return result
        } catch {
            endOperation()
            throw error
        }
    }

    public func executeUpdate(sql: String, parameters: [PostgresData] = []) async throws {
        try beginOperation()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let future: EventLoopFuture<Void> = self.pools.withConnection { connection in
                    connection.query(sql, parameters).map { _ in }
                }
                future.whenComplete { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                    }
                }
            }
            endOperation()
        } catch {
            endOperation()
            throw error
        }
    }

    public func execute(sql: String, parameters: [PostgresData] = []) async throws -> Int {
        try beginOperation()

        do {
            let result: Int = try await withCheckedThrowingContinuation { continuation in
                let future: EventLoopFuture<Int> = self.pools.withConnection { connection in
                    connection.query(sql, parameters).map { _ in 1 }
                }
                future.whenComplete { result in
                    switch result {
                    case .success(let count): continuation.resume(returning: count)
                    case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                    }
                }
            }
            endOperation()
            return result
        } catch {
            endOperation()
            throw error
        }
    }

    // MARK: - Transactions

    /// Reserve one physical session for a migration command. Session locks must
    /// span multiple transactions. Always retire this connection before releasing
    /// the pool slot, so locks and failed transactions cannot leak to another caller.
    internal func withMigrationSession<T: Sendable>(
        _ work: @Sendable (TransactionContext) async throws -> T
    ) async throws -> T {
        try beginOperation()
        defer { endOperation() }
        try Task.checkCancellation()
        let connection = try await requestMigrationConnection()
        defer { pools.releaseConnection(connection) }
        do {
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let result = try await work(TransactionContext(connection: connection))
                try Task.checkCancellation()
                return result
            } onCancel: {
                // Closing an owned session interrupts SQL and releases server locks.
                // The handler is removed before this connection is returned to the pool.
                let _: EventLoopFuture<Void> = connection.close()
            }
            try await connection.close()
            return result
        } catch {
            try? await connection.close()
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func requestMigrationConnection() async throws -> PostgresConnection {
        let request = MigrationConnectionRequest()
        // AsyncKit cannot remove a queued request. Track it until completion, even
        // if the caller has already cancelled; a late connection is released unused.
        try beginOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.install(continuation)
                pools.requestConnection().whenComplete { result in
                    if !request.complete(result), case .success(let connection) = result {
                        self.pools.releaseConnection(connection)
                    }
                    Task { await self.endOperation() }
                }
            }
        } onCancel: {
            request.cancel()
        }
    }

    public func transaction<T: Sendable>(
        _ work: @escaping @Sendable (TransactionContext) async throws -> T
    ) async throws -> T {
        try beginOperation()

        do {
            let result: T = try await withCheckedThrowingContinuation { continuation in
                let future: EventLoopFuture<T> = self.pools.withConnection { connection in
                    connection.query("BEGIN ISOLATION LEVEL READ COMMITTED").flatMap { _ in
                        let context = TransactionContext(connection: connection)

                        return connection.eventLoop.makeFutureWithTask {
                            try await work(context)
                        }
                        .flatMap { result in
                            connection.query("COMMIT").map { _ in result }
                        }
                        .flatMapError { error in
                            connection.query("ROLLBACK").flatMapErrorThrowing { rollbackError in
                                throw SpectroError.transactionAndRollbackFailed(
                                    original: error,
                                    rollback: rollbackError
                                )
                            }.flatMapThrowing { _ in
                                throw SpectroError.transactionFailed(underlying: error)
                            }
                        }
                    }
                }

                future.whenComplete { result in
                    continuation.resume(with: result)
                }
            }
            endOperation()
            return result
        } catch {
            endOperation()
            throw error
        }
    }

    // MARK: - Lifecycle

    public nonisolated var config: DatabaseConfiguration { configuration }

    /// Gracefully shuts down the database connection pool.
    ///
    /// Waits for all in-flight operations to complete before tearing down the
    /// pool, preventing SIGBUS crashes from NIO future callbacks referencing
    /// freed pool memory.
    public func shutdown() async {
        guard !isShutdown else { return }
        isShutdown = true

        if activeOperations > 0 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.shutdownContinuation = continuation
            }
        }

        syncShutdownPools()
        do {
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            // Best-effort; don't propagate
        }
    }

    private nonisolated func syncShutdownPools() {
        pools.shutdown()
    }

    // Best-effort sync teardown in deinit to prevent NIO SIGBUS when tests drop
    // a DatabaseConnection without calling shutdown(). Both pools.shutdown() and
    // syncShutdownGracefully() are idempotent, so double-shutdown is safe.
    // We cannot read isShutdown here (actor-isolated), so we always call —
    // the NIO internals guard against double-shutdown themselves.
    nonisolated public func syncShutdown() {
        pools.shutdown()
        try? eventLoopGroup.syncShutdownGracefully()
    }

    // MARK: - Health Check

    public func testConnection() async throws -> String {
        let result = try await executeQuery(
            sql: "SELECT version() as version",
            resultMapper: { row in
                let randomAccess = row.makeRandomAccess()
                guard let version = randomAccess[data: "version"].string else {
                    throw SpectroError.resultDecodingFailed(column: "version", expectedType: "String")
                }
                return version
            }
        )
        guard let version = result.first else {
            throw SpectroError.unexpectedResultCount(expected: 1, actual: 0)
        }
        return version
    }
}

// MARK: - DatabaseConfiguration

/// Connection credentials, pool sizing, and optional TLS settings for PostgreSQL.
///
/// Pass a value to ``Spectro/Spectro/init(configuration:)`` or a database connection.
/// See <doc:TransactionsAndConfiguration> for environment loading and lifecycle.
public struct DatabaseConfiguration: Sendable {
    public let hostname: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String
    public let maxConnectionsPerEventLoop: Int
    public let numberOfThreads: Int
    public let tlsConfiguration: TLSConfiguration?

    public init(
        hostname: String = "localhost",
        port: Int = 5432,
        username: String,
        password: String,
        database: String,
        maxConnectionsPerEventLoop: Int = 4,
        numberOfThreads: Int = System.coreCount,
        tlsConfiguration: TLSConfiguration? = nil
    ) {
        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.maxConnectionsPerEventLoop = maxConnectionsPerEventLoop
        self.numberOfThreads = numberOfThreads
        self.tlsConfiguration = tlsConfiguration
    }

    public static func fromEnvironment() throws -> DatabaseConfiguration {
        guard let username = ProcessInfo.processInfo.environment["DB_USER"] else {
            throw SpectroError.missingEnvironmentVariable("DB_USER")
        }
        guard let password = ProcessInfo.processInfo.environment["DB_PASSWORD"] else {
            throw SpectroError.missingEnvironmentVariable("DB_PASSWORD")
        }
        guard let database = ProcessInfo.processInfo.environment["DB_NAME"] else {
            throw SpectroError.missingEnvironmentVariable("DB_NAME")
        }
        let hostname = ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost"
        let port = Int(ProcessInfo.processInfo.environment["DB_PORT"] ?? "5432") ?? 5432
        return DatabaseConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database
        )
    }
}

// MARK: - TransactionContext
//
// `TransactionContext` is marked `@unchecked Sendable` with the following safety contract:
//
// 1. The wrapped `PostgresConnection` is pinned to a single NIO EventLoop for
//    the entire lifetime of the transaction.
// 2. `TransactionContext` instances are created inside `transaction()` and are
//    only valid within the transaction closure scope.
// 3. All operations on the connection are serialized by the EventLoop.
// 4. The context MUST NOT be stored or used after the transaction closure returns.
//
// This is safe because NIO's EventLoop guarantees single-threaded execution for
// all operations scheduled on it. The `@unchecked Sendable` allows passing the
// context to async closures that may resume on different threads, but all actual
// database operations are dispatched back to the connection's EventLoop.
//
// Remove this workaround when PostgresNIO adds native Sendable conformance.

public struct TransactionContext: @unchecked Sendable {
    let connection: PostgresConnection

    init(connection: PostgresConnection) {
        self.connection = connection
    }

    public func query<T: Sendable>(
        _ sql: String,
        _ parameters: [PostgresData] = [],
        mapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let future = connection.query(sql, parameters).flatMapThrowing { result in
                try result.rows.map(mapper)
            }
            future.whenComplete { result in
                switch result {
                case .success(let rows): continuation.resume(returning: rows)
                case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }

    public func execute(_ sql: String, _ parameters: [PostgresData] = []) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let future = connection.query(sql, parameters).map { _ in }
            future.whenComplete { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }
}

// MARK: - Internal

private enum DatabaseConnectionError: Error {
    case connectionClosed
    case invalidConfiguration
}

/// Synchronizes cancellation with a non-cancellable NIO pool request. The lock
/// protects only continuation ownership; callbacks always resume outside the lock.
private final class MigrationConnectionRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PostgresConnection, any Error>?
    private var cancelled = false
    private var completed = false

    func install(_ continuation: CheckedContinuation<PostgresConnection, any Error>) {
        let cancelled = lock.withLock {
            if self.cancelled { return true }
            self.continuation = continuation
            return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
    }

    func complete(_ result: Result<PostgresConnection, any Error>) -> Bool {
        let continuation = lock.withLock {
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }

    func cancel() {
        let continuation = lock.withLock {
            guard !completed else { return nil as CheckedContinuation<PostgresConnection, any Error>? }
            cancelled = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}
