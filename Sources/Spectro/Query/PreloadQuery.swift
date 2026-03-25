import Foundation
@preconcurrency import PostgresNIO
import SpectroCommon

/// Query that batch-loads relationships for a set of parent entities,
/// eliminating the N+1 query problem.
///
/// ## Usage
///
/// ```swift
/// // Load users with their posts in two queries total (not N+1)
/// let users = try await repo.query(User.self)
///     .where { $0.isActive == true }
///     .preload(\.$posts)            // FK inferred: "userId"
///     .preload(\.$profile)          // FK inferred: "userId"
///     .all()
///
/// // Override FK when it doesn't follow convention:
/// let posts = try await repo.query(Post.self)
///     .preload(\.$author, foreignKey: "authorId")
///     .all()
/// ```
public struct PreloadQuery<T: Schema>: Sendable {
    internal let baseQuery: Query<T>
    // Each preloader is a @Sendable closure that takes the current entities
    // and a repo, and returns updated entities with the relationship filled in.
    internal let preloaders: [@Sendable ([T], any Repo) async throws -> [T]]

    internal init(
        baseQuery: Query<T>,
        preloaders: [@Sendable ([T], any Repo) async throws -> [T]]
    ) {
        self.baseQuery = baseQuery
        self.preloaders = preloaders
    }

    // MARK: - Chaining Additional Preloads

    public func preload<Related: Schema>(
        _ keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        foreignKey: String? = nil
    ) -> PreloadQuery<T> {
        // Detect if this is a many-to-many relationship by checking the temp instance
        let tempInstance = T()
        let kind = tempInstance[keyPath: keyPath].relationshipInfo.kind
        if kind == .manyToMany {
            return PreloadQuery(
                baseQuery: baseQuery,
                preloaders: preloaders + [Self.manyToManyPreloader(keyPath: keyPath)]
            )
        }
        return PreloadQuery(
            baseQuery: baseQuery,
            preloaders: preloaders + [Self.hasManyPreloader(keyPath: keyPath, foreignKey: foreignKey)]
        )
    }

    public func preload<Related: Schema>(
        _ keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String? = nil
    ) -> PreloadQuery<T> {
        PreloadQuery(
            baseQuery: baseQuery,
            preloaders: preloaders + [Self.singlePreloader(keyPath: keyPath, foreignKey: foreignKey)]
        )
    }

    // MARK: - Query Chaining

    public func `where`(_ condition: (QueryBuilder<T>) -> QueryCondition) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.where(condition), preloaders: preloaders)
    }

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection = .asc) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.orderBy(field, direction), preloaders: preloaders)
    }

    public func limit(_ count: Int) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.limit(count), preloaders: preloaders)
    }

    public func offset(_ count: Int) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.offset(count), preloaders: preloaders)
    }

    // MARK: - Execution

    public func all() async throws -> [T] {
        let entities = try await baseQuery.all()
        guard !entities.isEmpty, !preloaders.isEmpty else { return entities }
        let repo: any Repo
        if let connection = baseQuery.executor as? DatabaseConnection {
            repo = GenericDatabaseRepo(connection: connection)
        } else if let context = baseQuery.executor as? TransactionContext {
            repo = TransactionRepo(context: context)
        } else {
            return entities
        }
        var result = entities
        for preloader in preloaders {
            result = try await preloader(result, repo)
        }
        return result
    }

    public func first() async throws -> T? {
        try await limit(1).all().first
    }

    // MARK: - Preloader Factory Methods

    // MARK: KeyPath Boxing for Sendable Closures
    //
    // `WritableKeyPath` has `@unchecked Sendable` conformance in Swift's stdlib,
    // but Swift 6.x's strict concurrency checker doesn't always propagate this
    // through generic type parameters in closure captures.
    //
    // `KPBox` wraps the keypath so closures can capture it without diagnostics.
    // This is safe because:
    // 1. `WritableKeyPath` is documented as Sendable by Apple
    // 2. The keypath itself is immutable after creation
    // 3. We only read the keypath, never mutate it
    //
    // This workaround can be removed when Swift's Sendable inference improves.
    private struct KPBox<Root, Value>: @unchecked Sendable {
        let value: WritableKeyPath<Root, Value>
    }

    /// Creates a preloader for a has-many relationship.
    /// FK is on the *related* table: `SELECT * FROM related WHERE fk IN (parentIds)`.
    static func hasManyPreloader<Related: Schema>(
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        foreignKey: String?
    ) -> @Sendable ([T], any Repo) async throws -> [T] {
        let fk = foreignKey ?? conventionalForeignKey(for: T.self)
        let box = KPBox(value: keyPath)
        return { entities, repo in
            try await batchLoadHasMany(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
        }
    }

    /// Creates a preloader for a has-one or belongs-to relationship.
    /// Reads `RelationshipInfo.kind` from a temporary instance to distinguish them.
    static func singlePreloader<Related: Schema>(
        keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String?
    ) -> @Sendable ([T], any Repo) async throws -> [T] {
        let tempInstance = T()
        let kind = tempInstance[keyPath: keyPath].relationshipInfo.kind
        let box = KPBox(value: keyPath)

        switch kind {
        case .hasOne:
            let fk = foreignKey ?? conventionalForeignKey(for: T.self)
            return { entities, repo in
                try await batchLoadHasOne(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
            }
        case .belongsTo:
            let fk = foreignKey ?? conventionalForeignKey(for: Related.self)
            return { entities, repo in
                try await batchLoadBelongsTo(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
            }
        default:
            let fk = foreignKey ?? conventionalForeignKey(for: T.self)
            return { entities, repo in
                try await batchLoadHasOne(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
            }
        }
    }

    /// Creates a preloader for a many-to-many relationship.
    /// Queries the junction table, then the related table, grouping results back to parents.
    static func manyToManyPreloader<Related: Schema>(
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>
    ) -> @Sendable ([T], any Repo) async throws -> [T] {
        let tempInstance = T()
        let relInfo = tempInstance[keyPath: keyPath].relationshipInfo
        let junctionTable = relInfo.junctionTable ?? ""
        let parentFK = (relInfo.parentForeignKey?.isEmpty == false)
            ? relInfo.parentForeignKey!
            : conventionalForeignKey(for: T.self)
        let relatedFK = (relInfo.relatedForeignKey?.isEmpty == false)
            ? relInfo.relatedForeignKey!
            : conventionalForeignKey(for: Related.self)
        let box = KPBox(value: keyPath)
        return { entities, repo in
            try await batchLoadManyToMany(
                entities: entities,
                keyPath: box.value,
                junctionTable: junctionTable,
                parentFK: parentFK,
                relatedFK: relatedFK,
                repo: repo
            )
        }
    }

    // MARK: - Batch Loading

    private static func batchLoadManyToMany<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        junctionTable: String,
        parentFK: String,
        relatedFK: String,
        repo: any Repo
    ) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkField = metadata.primaryKeyField else { return entities }

        var parentKeys: [AnyHashable] = []
        var parentParams: [PostgresData] = []
        for entity in entities {
            if let pair = extractPrimaryKeyPair(from: entity, fieldName: pkField) {
                parentKeys.append(pair.key)
                parentParams.append(pair.data)
            }
        }
        guard !parentKeys.isEmpty else { return entities }

        // Step 1: Query junction table for all rows matching parent IDs
        let junctionRows = try await batchFetchJunction(
            junctionTable: junctionTable,
            whereColumn: parentFK.snakeCase(),
            relatedColumn: relatedFK.snakeCase(),
            inParams: parentParams,
            repo: repo
        )

        // Build parent → [relatedId] mapping and collect unique related IDs
        var parentToRelatedIds: [AnyHashable: [AnyHashable]] = [:]
        var uniqueRelatedKeys = Set<AnyHashable>()
        var uniqueRelatedParams: [PostgresData] = []
        for (pId, rId, rData) in junctionRows {
            parentToRelatedIds[pId, default: []].append(rId)
            if uniqueRelatedKeys.insert(rId).inserted {
                uniqueRelatedParams.append(rData)
            }
        }

        guard !uniqueRelatedKeys.isEmpty else {
            // No junction rows found — return entities with empty arrays
            return entities.map { entity in
                var e = entity
                e[keyPath: keyPath] = SpectroLazyRelation(
                    loaded: [],
                    relationshipInfo: entity[keyPath: keyPath].relationshipInfo
                )
                return e
            }
        }

        // Step 2: Fetch related entities by their PK
        let relatedMeta = await SchemaRegistry.shared.register(Related.self)
        guard let relPK = relatedMeta.primaryKeyField else { return entities }

        let relatedEntities: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: relPK.snakeCase(),
            inParams: uniqueRelatedParams,
            repo: repo
        )

        var relatedIndex: [AnyHashable: Related] = [:]
        for r in relatedEntities {
            if let pair = extractPrimaryKeyPair(from: r, fieldName: relPK) {
                relatedIndex[pair.key] = r
            }
        }

        return entities.map { entity in
            var e = entity
            let parentId = extractPrimaryKeyPair(from: entity, fieldName: pkField)?.key
            let relatedIds = parentId.flatMap { parentToRelatedIds[$0] } ?? []
            let loaded = relatedIds.compactMap { relatedIndex[$0] }
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    private static func batchLoadHasMany<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        foreignKey: String,
        repo: any Repo
    ) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkField = metadata.primaryKeyField else { return entities }

        var parentParams: [PostgresData] = []
        for entity in entities {
            if let pair = extractPrimaryKeyPair(from: entity, fieldName: pkField) {
                parentParams.append(pair.data)
            }
        }
        guard !parentParams.isEmpty else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: foreignKey.snakeCase(),
            inParams: parentParams,
            repo: repo
        )

        var grouped: [AnyHashable: [Related]] = [:]
        for r in related {
            if let pair = extractPrimaryKeyPair(from: r, fieldName: foreignKey) {
                grouped[pair.key, default: []].append(r)
            }
        }

        return entities.map { entity in
            var e = entity
            let parentId = extractPrimaryKeyPair(from: entity, fieldName: pkField)?.key
            let loaded = parentId.flatMap { grouped[$0] } ?? []
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    private static func batchLoadHasOne<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String,
        repo: any Repo
    ) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkField = metadata.primaryKeyField else { return entities }

        var parentParams: [PostgresData] = []
        for entity in entities {
            if let pair = extractPrimaryKeyPair(from: entity, fieldName: pkField) {
                parentParams.append(pair.data)
            }
        }
        guard !parentParams.isEmpty else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: foreignKey.snakeCase(),
            inParams: parentParams,
            repo: repo
        )

        var grouped: [AnyHashable: Related] = [:]
        for r in related {
            if let pair = extractPrimaryKeyPair(from: r, fieldName: foreignKey),
               grouped[pair.key] == nil {
                grouped[pair.key] = r
            }
        }

        return entities.map { entity in
            var e = entity
            let parentId = extractPrimaryKeyPair(from: entity, fieldName: pkField)?.key
            let loaded: Related? = parentId.flatMap { grouped[$0] }
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    private static func batchLoadBelongsTo<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String,      // Column on T that holds the related entity's ID
        repo: any Repo
    ) async throws -> [T] {
        var seen = Set<AnyHashable>()
        var relatedParams: [PostgresData] = []
        for entity in entities {
            if let pair = extractPrimaryKeyPair(from: entity, fieldName: foreignKey),
               seen.insert(pair.key).inserted {
                relatedParams.append(pair.data)
            }
        }
        guard !relatedParams.isEmpty else { return entities }

        // Fetch related by primary key
        let relatedMeta = await SchemaRegistry.shared.register(Related.self)
        guard let relPK = relatedMeta.primaryKeyField else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: relPK.snakeCase(),
            inParams: relatedParams,
            repo: repo
        )

        var index: [AnyHashable: Related] = [:]
        for r in related {
            if let pair = extractPrimaryKeyPair(from: r, fieldName: relPK) { index[pair.key] = r }
        }

        return entities.map { entity in
            var e = entity
            let fkVal = extractPrimaryKeyPair(from: entity, fieldName: foreignKey)?.key
            let loaded: Related? = fkVal.flatMap { index[$0] }
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    // MARK: - Shared Query Helper

    /// Execute `SELECT * FROM table WHERE column IN (params)`.
    /// The column name is already snake_cased at the call sites above.
    /// Accepts pre-built `[PostgresData]` so callers can pass any PK type.
    private static func batchFetch<Related: Schema>(
        relatedType: Related.Type,
        whereColumn: String,
        inParams: [PostgresData],
        repo: any Repo
    ) async throws -> [Related] {
        guard !inParams.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: inParams.count).joined(separator: ", ")
        let condition = QueryCondition(
            sql: "\"\(whereColumn)\" IN (\(placeholders))",
            parameters: inParams
        )
        return try await repo.query(relatedType).where { _ in condition }.all()
    }

    /// Execute `SELECT parentFK, relatedFK FROM junction WHERE parentFK IN (params)`.
    /// Returns an array of (parentKey, relatedKey, relatedData) tuples from the junction table.
    /// The third element carries the `PostgresData` for the related ID so callers can pass it
    /// directly to `batchFetch` without lossy conversions.
    private static func batchFetchJunction(
        junctionTable: String,
        whereColumn: String,
        relatedColumn: String,
        inParams: [PostgresData],
        repo: any Repo
    ) async throws -> [(AnyHashable, AnyHashable, PostgresData)] {
        guard !inParams.isEmpty else { return [] }
        let placeholders = (1...inParams.count).map { "$\($0)" }.joined(separator: ", ")
        let sql = """
            SELECT "\(whereColumn)", "\(relatedColumn)" FROM "\(junctionTable)" WHERE "\(whereColumn)" IN (\(placeholders))
            """

        let rows = try await repo.executeRawQuery(
            sql: sql,
            parameters: inParams
        )

        var result: [(AnyHashable, AnyHashable, PostgresData)] = []
        for row in rows {
            let ra = row.makeRandomAccess()
            let parentData = ra[data: whereColumn]
            let relatedData = ra[data: relatedColumn]
            if let parentKey = anyHashableFromPostgresData(parentData),
               let relatedKey = anyHashableFromPostgresData(relatedData) {
                result.append((parentKey, relatedKey, relatedData))
            }
        }
        return result
    }

    /// Extract an `AnyHashable` value from `PostgresData`, supporting UUID, Int, and String.
    private static func anyHashableFromPostgresData(_ data: PostgresData) -> AnyHashable? {
        if let v = data.uuid { return AnyHashable(v) }
        if let v = data.int { return AnyHashable(v) }
        if let v = data.string { return AnyHashable(v) }
        return nil
    }

    // MARK: - Helpers

    /// Extract a primary key from any @ID, @ForeignKey, or bare UUID/Int/String property by name.
    /// Returns both the hashable key (for dictionary grouping) and PostgresData (for SQL params).
    static func extractPrimaryKeyPair<S: Schema>(from entity: S, fieldName: String) -> (key: AnyHashable, data: PostgresData)? {
        for child in Mirror(reflecting: entity).children {
            guard let label = child.label else { continue }
            let name = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard name == fieldName else { continue }
            if let v = child.value as? any PrimaryKeyWrapperProtocol {
                return (v.primaryKeyHashable, v.primaryKeyPostgresData)
            }
            if let v = child.value as? any ForeignKeyWrapperProtocol {
                return (v.foreignKeyHashable, v.foreignKeyPostgresData)
            }
            if let v = child.value as? UUID { return (AnyHashable(v), PostgresData(uuid: v)) }
            if let v = child.value as? Int { return (AnyHashable(v), PostgresData(int: v)) }
            if let v = child.value as? String { return (AnyHashable(v), PostgresData(string: v)) }
        }
        return nil
    }

    /// Convention-based FK: "User" → "userId", "BlogPost" → "blogPostId".
    static func conventionalForeignKey(for type: any Schema.Type) -> String {
        let name = String(describing: type)
        return name.prefix(1).lowercased() + name.dropFirst() + "Id"
    }
}
