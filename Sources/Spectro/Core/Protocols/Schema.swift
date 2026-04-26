public protocol Schema: Sendable {
    static var tableName: String { get }
    init()
    /// KeyPath → Swift property name mapping for cross-platform query building.
    /// On Linux, `String(describing: keyPath)` produces garbage — this provides
    /// the reliable source of truth. Generated automatically by `@Schema` macro;
    /// manual schemas should provide their own.
    static var _keyPathToColumn: [AnyKeyPath: String] { get }
    /// The snake_case database column name of the `@SoftDelete` field, or `nil` for hard-delete schemas.
    /// Must be a protocol requirement (not just an extension default) for generic dispatch to work.
    static var softDeleteColumn: String? { get }
}

extension Schema {
    // AnyKeyPath is not Sendable, but the dictionary is immutable
    // and only read after initialization.
    nonisolated public static var _keyPathToColumn: [AnyKeyPath: String] { [:] }

    /// The snake_case database column name of the `@SoftDelete` field, or `nil`.
    /// Overridden by the `@Schema` macro when a `@SoftDelete` field is detected.
    /// Used by `Query.buildSQL()` to inject an automatic `WHERE deleted_at IS NULL` filter.
    nonisolated public static var softDeleteColumn: String? { nil }
}
