import Foundation
import PostgresNIO
import SpectroCommon

/// Query that includes joined tables and returns combined results
public struct JoinQuery<T: Schema, U: Schema>: Sendable {
    private let baseQuery: Query<T>
    private let joinedSchema: U.Type
    private let joinClause: JoinClause

    internal init(baseQuery: Query<T>, joinedSchema: U.Type, joinClause: JoinClause) {
        self.baseQuery = baseQuery
        self.joinedSchema = joinedSchema
        self.joinClause = joinClause
    }

    /// Execute join query and return tuples of (main, joined) records
    public func all() async throws -> [(T, U?)] {
        let sql = buildJoinSQL()

        return try await baseQuery.executor.executeQuery(
            sql: sql,
            parameters: baseQuery.parameters,
            resultMapper: { row in
                let mainRecord = try T.fromSync(row: row)
                let joinedRecord: U?
                do {
                    joinedRecord = try U.fromSync(row: row)
                } catch {
                    joinedRecord = nil
                }
                return (mainRecord, joinedRecord)
            }
        )
    }

    /// Execute query and return first result
    public func first() async throws -> (T, U?)? {
        try await limit(1).all().first
    }

    /// Add where conditions to the join query
    public func `where`(_ condition: (JoinQueryBuilder<T, U>) -> QueryCondition) -> JoinQuery<T, U> {
        let builder = JoinQueryBuilder<T, U>()
        let queryCondition = condition(builder)

        var newBaseQuery = baseQuery
        if newBaseQuery.whereClause.isEmpty {
            newBaseQuery.whereClause = queryCondition.sql
        } else {
            newBaseQuery.whereClause += " AND (\(queryCondition.sql))"
        }
        newBaseQuery.parameters.append(contentsOf: queryCondition.parameters)

        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }

    /// Add ordering to the join query
    public func orderBy<V>(_ field: (JoinQueryBuilder<T, U>) -> JoinField<V>, _ direction: OrderDirection = .asc) -> JoinQuery<T, U> {
        let builder = JoinQueryBuilder<T, U>()
        let joinField = field(builder)

        var newBaseQuery = baseQuery
        // qualifiedName is already pre-quoted ("table"."column")
        newBaseQuery.orderFields.append(OrderByClause(field: joinField.qualifiedName, direction: direction))

        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }

    /// Limit results
    public func limit(_ count: Int) -> JoinQuery<T, U> {
        var newBaseQuery = baseQuery
        newBaseQuery.limitValue = count
        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }

    /// Offset results
    public func offset(_ count: Int) -> JoinQuery<T, U> {
        var newBaseQuery = baseQuery
        newBaseQuery.offsetValue = count
        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }

    // MARK: - Private

    private func buildJoinSQL() -> String {
        let mainTable = T.tableName
        let joinTable = U.tableName

        var sql = "SELECT \(mainTable.quoted).*, \(joinTable.quoted).* FROM \(mainTable.quoted)"
        sql += " \(joinClause.type.sql) \(joinTable.quoted) ON \(joinClause.condition)"

        if !baseQuery.whereClause.isEmpty {
            sql += " WHERE \(baseQuery.whereClause)"
        }
        if !baseQuery.orderFields.isEmpty {
            let orderClause = baseQuery.orderFields
                .map { "\($0.field) \($0.direction.sql)" }
                .joined(separator: ", ")
            sql += " ORDER BY \(orderClause)"
        }
        if let limit = baseQuery.limitValue {
            sql += " LIMIT \(limit)"
        }
        if let offset = baseQuery.offsetValue {
            sql += " OFFSET \(offset)"
        }

        return sql
    }
}

// MARK: - JoinQueryBuilder

/// Builder for creating conditions on joined queries
@dynamicMemberLookup
public struct JoinQueryBuilder<T: Schema, U: Schema>: Sendable {
    public init() {}

    public var main: JoinQueryField<T> { JoinQueryField<T>(tableName: T.tableName) }
    public var joined: JoinQueryField<U> { JoinQueryField<U>(tableName: U.tableName) }

    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> JoinField<V> {
        JoinField<V>(tableName: T.tableName, fieldName: extractFieldName(from: keyPath, schema: T.self))
    }
}

// MARK: - Query Extensions for JOIN execution

extension Query {
    /// Execute as a typed join query.
    ///
    /// - Throws: `SpectroError.invalidSchema` if no join for `joinedType` was added via `.join()` first.
    public func executeJoin<U: Schema>(with joinedType: U.Type) throws -> JoinQuery<T, U> {
        guard let joinClause = joins.first(where: { $0.table == joinedType.tableName }) else {
            throw SpectroError.invalidSchema(
                reason: "No join found for schema type \(joinedType). Call .join() or .leftJoin() before .executeJoin(with:)."
            )
        }
        return JoinQuery(baseQuery: self, joinedSchema: joinedType, joinClause: joinClause)
    }

    /// Convenience: join and execute in one call
    public func joinAndExecute<U: Schema>(
        _ joinSchema: U.Type,
        on condition: (JoinBuilder<T, U>) -> QueryCondition
    ) async throws -> [(T, U?)] {
        try await self
            .join(joinSchema, on: condition)
            .executeJoin(with: joinSchema)
            .all()
    }

    /// Convenience: left join and execute in one call
    public func leftJoinAndExecute<U: Schema>(
        _ joinSchema: U.Type,
        on condition: (JoinBuilder<T, U>) -> QueryCondition
    ) async throws -> [(T, U?)] {
        try await self
            .leftJoin(joinSchema, on: condition)
            .executeJoin(with: joinSchema)
            .all()
    }
}
