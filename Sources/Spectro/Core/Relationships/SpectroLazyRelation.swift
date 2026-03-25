import Foundation
@preconcurrency import PostgresNIO

/// Core lazy relation type for relationship loading.
///
/// All state changes happen through value-copying (`withLoaded(_:)`, `withLoader(_:)`),
/// making this type safe to pass across actor boundaries.
///
/// ## Loading Strategies
///
/// There are two ways to load a relationship:
///
/// 1. **Loader closure** (preferred): Attach a type-erased loader via `withLoader(_:)`.
///    The loader captures the parent ID and foreign key at injection time, so
///    `load(using:)` can execute the query without knowing the concrete Schema type.
///    Use the static factory methods (`hasManyLoader`, `hasOneLoader`, `belongsToLoader`)
///    to create loaders.
///
/// 2. **Typed `load(from:...)` methods**: Pass the parent entity and child type
///    explicitly. These are defined in extensions below and delegate to
///    `RelationshipLoader`.
///
/// For batch loading (N+1 prevention), use `Query<T>.preload(\.$relationship)`.
public struct SpectroLazyRelation<T: Sendable>: Sendable {

    /// Loading state for a lazy relationship.
    public enum LoadState: Sendable {
        case notLoaded
        case loading
        indirect case loaded(T)
        /// The relationship failed to load.
        ///
        /// The associated error is constrained to `Sendable` so `LoadState`
        /// itself remains `Sendable`. Wrap non-Sendable errors in a
        /// `Sendable` container before storing them here.
        case error(any Error & Sendable)
    }

    private var loadState: LoadState
    // internal so PreloadQuery can read the kind/foreignKey when injecting loaded data
    internal let relationshipInfo: RelationshipInfo
    /// Type-erased loader closure, captured at injection time when concrete types are known.
    private let loader: (@Sendable (GenericDatabaseRepo) async throws -> T)?

    // MARK: - Init

    public init(relationshipInfo: RelationshipInfo) {
        self.loadState = .notLoaded
        self.relationshipInfo = relationshipInfo
        self.loader = nil
    }

    public init(loaded data: T, relationshipInfo: RelationshipInfo) {
        self.loadState = .loaded(data)
        self.relationshipInfo = relationshipInfo
        self.loader = nil
    }

    public init() {
        self.loadState = .notLoaded
        self.relationshipInfo = RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasMany,
            foreignKey: ""
        )
        self.loader = nil
    }

    /// Internal initializer that preserves all fields including the loader.
    private init(
        loadState: LoadState,
        relationshipInfo: RelationshipInfo,
        loader: (@Sendable (GenericDatabaseRepo) async throws -> T)?
    ) {
        self.loadState = loadState
        self.relationshipInfo = relationshipInfo
        self.loader = loader
    }

    // MARK: - State Access

    public var isLoaded: Bool {
        if case .loaded = loadState { return true }
        return false
    }

    public var value: T? {
        if case .loaded(let data) = loadState { return data }
        return nil
    }

    public var state: LoadState { loadState }

    // MARK: - Loader Injection

    /// Creates a copy of this relation with the given loader closure attached.
    ///
    /// The load state is reset to `.notLoaded` so that calling `load(using:)`
    /// will invoke the new loader instead of returning stale cached data.
    /// This is essential when `build(from:)` injects loaders into relations
    /// that were initialized with default values (e.g. `self.posts = []`
    /// sets the state to `.loaded([])`).
    ///
    /// ```swift
    /// let relation = relation.withLoader(
    ///     SpectroLazyRelation.hasManyLoader(parentId: user.id, foreignKey: "user_id")
    /// )
    /// let posts = try await relation.load(using: repo)
    /// ```
    public func withLoader(
        _ loader: @escaping @Sendable (GenericDatabaseRepo) async throws -> T
    ) -> SpectroLazyRelation<T> {
        SpectroLazyRelation(
            loadState: .notLoaded,
            relationshipInfo: relationshipInfo,
            loader: loader
        )
    }

    // MARK: - Loading

    /// Load the relationship using the stored loader closure.
    ///
    /// If the relationship is already loaded, returns the cached value.
    /// If no loader has been attached, throws `.notImplemented` with guidance
    /// on alternative loading approaches.
    public mutating func load(using repo: GenericDatabaseRepo) async throws -> T {
        if case .loaded(let data) = loadState { return data }

        guard let loader = loader else {
            throw SpectroError.notImplemented(
                "SpectroLazyRelation.load(using:) has no loader for '\(relationshipInfo.relatedTypeName)'. "
                + "Attach a loader via withLoader(_:) using the static factory methods "
                + "(hasManyLoader, hasOneLoader, belongsToLoader), "
                + "or use the typed API: entity.load(from:childType:using:). "
                + "For batch loading, use Query<Parent>.preload(\\.$\(relationshipInfo.name))."
            )
        }

        self.loadState = .loading
        do {
            let result = try await loader(repo)
            self.loadState = .loaded(result)
            return result
        } catch {
            self.loadState = .error(error)
            throw error
        }
    }

    public func withLoaded(_ data: T) -> SpectroLazyRelation<T> {
        SpectroLazyRelation(
            loadState: .loaded(data),
            relationshipInfo: relationshipInfo,
            loader: loader
        )
    }

    // MARK: - Loader Factory Methods
    //
    // These static methods create type-erased loader closures that capture the
    // parent's ID (or FK value) and the foreign key column name at creation
    // time. The returned closure is @Sendable and uses the repo's query API
    // to execute the actual database query.

    /// Creates a loader for a has-many relationship.
    ///
    /// The loader executes: `SELECT * FROM <Child.tableName> WHERE <foreignKey> = <parentId>`
    ///
    /// - Parameters:
    ///   - parentId: The parent entity's primary key value (any `PrimaryKeyType`: UUID, Int, String, etc.).
    ///   - foreignKey: The column on the child table that references the parent (already snake_cased).
    /// - Returns: A `@Sendable` closure suitable for `withLoader(_:)`.
    public static func hasManyLoader<Child: Schema, PK: PrimaryKeyType>(
        parentId: PK,
        foreignKey: String
    ) -> @Sendable (GenericDatabaseRepo) async throws -> [Child] where T == [Child] {
        return { repo in
            let condition = QueryCondition(
                sql: "\(foreignKey.quoted) = ?",
                parameters: [parentId.toPostgresData()]
            )
            return try await repo.query(Child.self).where { _ in condition }.all()
        }
    }

    /// Creates a loader for a has-one relationship.
    ///
    /// The loader executes: `SELECT * FROM <Child.tableName> WHERE <foreignKey> = <parentId> LIMIT 1`
    ///
    /// - Parameters:
    ///   - parentId: The parent entity's primary key value (any `PrimaryKeyType`: UUID, Int, String, etc.).
    ///   - foreignKey: The column on the child table that references the parent (already snake_cased).
    /// - Returns: A `@Sendable` closure suitable for `withLoader(_:)`.
    public static func hasOneLoader<Child: Schema, PK: PrimaryKeyType>(
        parentId: PK,
        foreignKey: String
    ) -> @Sendable (GenericDatabaseRepo) async throws -> Child? where T == Child? {
        return { repo in
            let condition = QueryCondition(
                sql: "\(foreignKey.quoted) = ?",
                parameters: [parentId.toPostgresData()]
            )
            return try await repo.query(Child.self).where { _ in condition }.first()
        }
    }

    /// Creates a loader for a belongs-to relationship.
    ///
    /// The loader executes: `SELECT * FROM <Parent.tableName> WHERE id = <foreignKeyValue> LIMIT 1`
    ///
    /// - Parameters:
    ///   - foreignKeyValue: The FK value stored on the child entity, pointing to the parent's PK (any `PrimaryKeyType`).
    /// - Returns: A `@Sendable` closure suitable for `withLoader(_:)`.
    public static func belongsToLoader<Parent: Schema, PK: PrimaryKeyType>(
        foreignKeyValue: PK
    ) -> @Sendable (GenericDatabaseRepo) async throws -> Parent? where T == Parent? {
        return { repo in
            try await repo.get(Parent.self, id: foreignKeyValue)
        }
    }
}

// MARK: - Typed Loading (HasMany)
//
// These constrained extensions provide load(from:using:) which accepts the
// parent entity with its concrete type, enabling actual database queries.

extension SpectroLazyRelation where T == [any Schema] {
    public static var empty: SpectroLazyRelation<T> {
        SpectroLazyRelation(loaded: [], relationshipInfo: RelationshipInfo(
            name: "", relatedTypeName: "", kind: .hasMany, foreignKey: ""
        ))
    }
}

extension SpectroLazyRelation where T: Schema {
    public static var empty: SpectroLazyRelation<T?> {
        SpectroLazyRelation<T?>(loaded: nil, relationshipInfo: RelationshipInfo(
            name: "", relatedTypeName: String(describing: T.self), kind: .hasOne, foreignKey: ""
        ))
    }
}

// MARK: - Typed Load from Parent

extension SpectroLazyRelation {

    /// Load a has-many relationship given the parent entity.
    ///
    /// This method bridges to `RelationshipLoader.loadHasMany` using the
    /// concrete parent and child types so that a real database query can be
    /// executed.
    ///
    /// ```swift
    /// let posts = try await user.$posts.load(from: user, childType: Post.self, using: repo)
    /// ```
    public func load<Parent: Schema, Child: Schema>(
        from parent: Parent,
        childType: Child.Type,
        using repo: GenericDatabaseRepo
    ) async throws -> [Child] where T == [Child] {
        if case .loaded(let data) = loadState { return data }
        let fk = relationshipInfo.foreignKey
            ?? PreloadQuery<Parent>.conventionalForeignKey(for: Parent.self)
        return try await RelationshipLoader.loadHasMany(
            for: parent,
            relationship: relationshipInfo.name,
            childType: childType,
            foreignKey: fk,
            using: repo
        )
    }

    /// Load a has-one relationship given the parent entity.
    ///
    /// ```swift
    /// let profile = try await user.$profile.load(from: user, relatedType: Profile.self, using: repo)
    /// ```
    public func load<Parent: Schema, Related: Schema>(
        from parent: Parent,
        relatedType: Related.Type,
        using repo: GenericDatabaseRepo
    ) async throws -> Related? where T == Related? {
        if case .loaded(let data) = loadState { return data }

        switch relationshipInfo.kind {
        case .hasOne:
            let fk = relationshipInfo.foreignKey
                ?? PreloadQuery<Parent>.conventionalForeignKey(for: Parent.self)
            return try await RelationshipLoader.loadHasOne(
                for: parent,
                relationship: relationshipInfo.name,
                childType: relatedType,
                foreignKey: fk,
                using: repo
            )
        case .belongsTo:
            let fk = relationshipInfo.foreignKey
                ?? PreloadQuery<Related>.conventionalForeignKey(for: Related.self)
            return try await RelationshipLoader.loadBelongsTo(
                for: parent,
                relationship: relationshipInfo.name,
                parentType: relatedType,
                foreignKey: fk,
                using: repo
            )
        default:
            throw SpectroError.relationshipError(
                from: String(describing: Parent.self),
                to: String(describing: Related.self),
                reason: "Expected hasOne or belongsTo but got \(relationshipInfo.kind)"
            )
        }
    }
}
