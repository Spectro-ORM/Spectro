import PostgresNIO

/// Abstraction over query execution, allowing `Query<T>` to work with both
/// pooled connections (`DatabaseConnection`) and pinned transaction connections (`TransactionContext`).
public protocol QueryExecutor: Sendable {
    func executeQuery<T: Sendable>(
        sql: String,
        parameters: [PostgresData],
        resultMapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T]
}

extension DatabaseConnection: QueryExecutor {}

extension TransactionContext: QueryExecutor {
    public func executeQuery<T: Sendable>(
        sql: String,
        parameters: [PostgresData],
        resultMapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T] {
        try await self.query(sql, parameters, mapper: resultMapper)
    }
}
