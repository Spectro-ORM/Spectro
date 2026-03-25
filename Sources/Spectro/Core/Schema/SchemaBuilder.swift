import Foundation
@preconcurrency import PostgresNIO
import SpectroCommon

/// Protocol for building schema instances from database rows.
///
/// Implement this to eliminate runtime reflection on the hot path.
/// Use the `@Schema` macro to generate the implementation automatically.
///
/// ```swift
/// @Schema
/// struct User: Schema { ... }
/// // @Schema generates:
/// // extension User: SchemaBuilder {
/// //     public static func build(from values: [String: Any]) -> User { ... }
/// // }
/// ```
public protocol SchemaBuilder: Schema {
    static func build(from values: [String: Any]) -> Self
}

/// Default no-op implementation. Concrete types should override via
/// `@Schema` macro or a manual `SchemaBuilder` conformance.
extension SchemaBuilder {
    public static func build(from values: [String: Any]) -> Self {
        Self()
    }
}

// MARK: - Row Mapping

extension Schema {
    /// Synchronous row mapping for contexts where async is unavailable.
    ///
    /// Uses `Mirror` reflection on a default instance to discover field names,
    /// extracts matching column values from the row, and delegates to
    /// `SchemaBuilder.build(from:)` or `MutableSchema.apply(values:)`.
    public static func fromSync(row: PostgresRow) throws -> Self {
        let instance = Self()
        let randomAccess = row.makeRandomAccess()
        var values: [String: Any] = [:]

        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            let dbColumn: String
            if let overridable = child.value as? ColumnNameOverridable,
               let override = overridable.columnName {
                dbColumn = override
            } else {
                dbColumn = fieldName.snakeCase()
            }
            let dbValue = randomAccess[data: dbColumn]

            if let v = dbValue.uuid        { values[fieldName] = v }
            else if let v = dbValue.string  { values[fieldName] = v }
            else if let v = dbValue.int     { values[fieldName] = v }
            else if let v = dbValue.bool    { values[fieldName] = v }
            else if let v = dbValue.date    { values[fieldName] = v }
            else if let v = dbValue.double  { values[fieldName] = v }
            else if let v = dbValue.float   { values[fieldName] = v }
        }

        return try buildInstance(from: values)
    }

    private static func buildInstance(from values: [String: Any]) throws -> Self {
        if let builderType = self as? any SchemaBuilder.Type {
            let built = builderType.build(from: values)
            guard let result = built as? Self else {
                throw SpectroError.invalidSchema(
                    reason: "SchemaBuilder.build(from:) returned incompatible type for \(Self.self)"
                )
            }
            return result
        }
        if var mutable = Self() as? MutableSchema {
            mutable.apply(values: values)
            guard let result = mutable as? Self else {
                throw SpectroError.invalidSchema(
                    reason: "MutableSchema.apply(values:) returned incompatible type for \(Self.self)"
                )
            }
            return result
        }
        throw SpectroError.invalidSchema(
            reason: "Schema \(Self.self) must conform to SchemaBuilder (use @Schema macro) or MutableSchema"
        )
    }

    /// Map a PostgreSQL row to a schema instance.
    ///
    /// 1. Registers the schema with `SchemaRegistry` to obtain field metadata.
    /// 2. Extracts each column value using the `FieldType` enum — no metatype
    ///    traffic across actor boundaries.
    /// 3. Delegates construction to `SchemaBuilder.build(from:)` if available,
    ///    otherwise falls back to `MutableSchema.apply(values:)`.
    public static func from(row: PostgresRow) async throws -> Self {
        let metadata = await SchemaRegistry.shared.register(self)
        let randomAccess = row.makeRandomAccess()

        var values: [String: Any] = [:]

        for field in metadata.fields {
            let dbValue = randomAccess[data: field.databaseName]

            switch field.fieldType {
            case .string:
                if let v = dbValue.string  { values[field.name] = v }
            case .int:
                if let v = dbValue.int     { values[field.name] = v }
            case .bool:
                if let v = dbValue.bool    { values[field.name] = v }
            case .uuid:
                if let v = dbValue.uuid    { values[field.name] = v }
            case .date:
                if let v = dbValue.date    { values[field.name] = v }
            case .double:
                if let v = dbValue.double  { values[field.name] = v }
            case .float:
                if let v = dbValue.float   { values[field.name] = v }
            }
        }

        return try buildInstance(from: values)
    }
}
