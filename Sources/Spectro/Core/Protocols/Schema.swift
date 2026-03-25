public protocol Schema: Sendable {
    static var tableName: String { get }
    init()
    /// KeyPath → Swift property name mapping for cross-platform query building.
    /// On Linux, `String(describing: keyPath)` produces garbage — this provides
    /// the reliable source of truth. Generated automatically by `@Schema` macro;
    /// manual schemas should provide their own.
    static var _keyPathToColumn: [AnyKeyPath: String] { get }
}

extension Schema {
    // AnyKeyPath is not Sendable, but the dictionary is immutable
    // and only read after initialization.
    nonisolated public static var _keyPathToColumn: [AnyKeyPath: String] { [:] }
}
