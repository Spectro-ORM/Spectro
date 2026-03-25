import Foundation
import PostgresKit

/// Types that can serve as primary keys in Spectro schemas.
///
/// Conform to this protocol to use a type as an `@ID` or `@ForeignKey` value.
/// Built-in conformances: `UUID`, `Int`, `String`.
public protocol PrimaryKeyType: Sendable, Hashable, Codable {
    /// Converts this value to `PostgresData` for query parameters.
    func toPostgresData() -> PostgresData

    /// Attempts to decode a value from a `PostgresData` cell.
    static func fromPostgresData(_ data: PostgresData) -> Self?

    /// The default value for uninitialized primary keys.
    static var defaultValue: Self { get }

    /// The corresponding `FieldType` for schema metadata.
    static var fieldType: FieldType { get }
}

// MARK: - Built-in Conformances

extension UUID: PrimaryKeyType {
    public func toPostgresData() -> PostgresData { PostgresData(uuid: self) }
    public static func fromPostgresData(_ data: PostgresData) -> UUID? { data.uuid }
    public static var defaultValue: UUID { UUID() }
    public static var fieldType: FieldType { .uuid }
}

extension Int: PrimaryKeyType {
    public func toPostgresData() -> PostgresData { PostgresData(int: self) }
    public static func fromPostgresData(_ data: PostgresData) -> Int? { data.int }
    public static var defaultValue: Int { 0 }
    public static var fieldType: FieldType { .int }
}

extension String: PrimaryKeyType {
    public func toPostgresData() -> PostgresData { PostgresData(string: self) }
    public static func fromPostgresData(_ data: PostgresData) -> String? { data.string }
    public static var defaultValue: String { "" }
    public static var fieldType: FieldType { .string }
}

// MARK: - Marker Protocols for Reflection

/// Non-generic marker protocol for runtime type checking of `ID<T>` via Mirror.
public protocol PrimaryKeyWrapperProtocol {
    /// The wrapped primary key value as `PostgresData`.
    var primaryKeyPostgresData: PostgresData { get }

    /// The `FieldType` of this primary key.
    var primaryKeyFieldType: FieldType { get }

    /// The wrapped value as `AnyHashable` for dictionary keying.
    var primaryKeyHashable: AnyHashable { get }
}

/// Non-generic marker protocol for runtime type checking of `ForeignKey<T>` via Mirror.
public protocol ForeignKeyWrapperProtocol {
    /// The wrapped foreign key value as `PostgresData`.
    var foreignKeyPostgresData: PostgresData { get }

    /// The `FieldType` of this foreign key.
    var foreignKeyFieldType: FieldType { get }

    /// The wrapped value as `AnyHashable` for dictionary keying.
    var foreignKeyHashable: AnyHashable { get }

    /// The column name override, if any.
    var foreignKeyColumnName: String? { get }
}
