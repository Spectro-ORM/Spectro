import Foundation
@preconcurrency import PostgresNIO

/// Core repository protocol for database operations
public protocol Repo: Sendable {
    func get<T: Schema>(_ schema: T.Type, id: some PrimaryKeyType) async throws -> T?
    func getOrFail<T: Schema>(_ schema: T.Type, id: some PrimaryKeyType) async throws -> T
    func all<T: Schema>(_ schema: T.Type) async throws -> [T]
    func insert<T: Schema>(_ instance: T, includePrimaryKey: Bool) async throws -> T
    func upsert<T: Schema>(_ instance: T, conflictTarget: ConflictTarget, set: [String]?, includePrimaryKey: Bool) async throws -> T
    func insertAll<T: Schema>(_ instances: [T], includePrimaryKey: Bool) async throws -> [T]
    func update<T: Schema>(_ schema: T.Type, id: some PrimaryKeyType, changes: [String: any Sendable]) async throws -> T
    func delete<T: Schema>(_ schema: T.Type, id: some PrimaryKeyType) async throws
    func transaction<T: Sendable>(_ work: @escaping @Sendable (any Repo) async throws -> T) async throws -> T
    func query<T: Schema>(_ schema: T.Type) -> Query<T>
    func executeRawSQL(_ sql: String) async throws
    func executeRawQuery(sql: String, parameters: [PostgresData]) async throws -> [PostgresRow]
}

extension Repo {
    public func insert<T: Schema>(_ instance: T) async throws -> T {
        try await insert(instance, includePrimaryKey: false)
    }

    public func upsert<T: Schema>(_ instance: T, conflictTarget: ConflictTarget, set: [String]? = nil) async throws -> T {
        try await upsert(instance, conflictTarget: conflictTarget, set: set, includePrimaryKey: false)
    }

    public func insertAll<T: Schema>(_ instances: [T]) async throws -> [T] {
        try await insertAll(instances, includePrimaryKey: false)
    }

    public func executeRawQuery(sql: String) async throws -> [PostgresRow] {
        try await executeRawQuery(sql: sql, parameters: [])
    }

    // MARK: - Changeset

    /// Insert a new record from a validated changeset.
    ///
    /// Builds an instance from the changeset's changes using `SchemaBuilder.build(from:)`,
    /// then delegates to the standard `insert(_:)`. Requires `T: SchemaBuilder`.
    public func insert<T: Schema & SchemaBuilder>(_ changeset: Changeset<T>) async throws -> T {
        let changes = try changeset.applyChanges()
        guard !changes.isEmpty else {
            throw SpectroError.invalidSchema(reason: "Cannot insert from a changeset with no changes")
        }
        var anyChanges: [String: Any] = [:]
        for (key, value) in changes {
            anyChanges[key] = value
        }
        let instance = T.build(from: anyChanges)
        return try await insert(instance)
    }

    /// Update an existing record from a validated changeset.
    ///
    /// Extracts the primary key from `changeset.data` and delegates to `update(_:id:changes:)`.
    public func update<T: Schema>(_ changeset: Changeset<T>) async throws -> T {
        guard let existingData = changeset.data else {
            throw SpectroError.invalidSchema(
                reason: "Cannot update from a changeset with no existing data. Use insert(_:) for new records."
            )
        }

        let changes = try changeset.applyChanges()
        guard !changes.isEmpty else {
            return existingData
        }

        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkFieldName = metadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(T.self) has no primary key field")
        }

        let mirror = Mirror(reflecting: existingData)
        var pkValue: (any PrimaryKeyType)?
        for child in mirror.children {
            guard let label = child.label else { continue }
            let name = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard name == pkFieldName else { continue }

            let wrapperMirror = Mirror(reflecting: child.value)
            for wrapperChild in wrapperMirror.children {
                if wrapperChild.label == "wrappedValue" {
                    pkValue = wrapperChild.value as? (any PrimaryKeyType)
                    break
                }
            }
            if pkValue == nil {
                pkValue = child.value as? (any PrimaryKeyType)
            }
            break
        }

        guard let id = pkValue else {
            throw SpectroError.invalidSchema(
                reason: "Could not extract primary key value from \(T.self)"
            )
        }

        return try await update(T.self, id: id, changes: changes)
    }
}
