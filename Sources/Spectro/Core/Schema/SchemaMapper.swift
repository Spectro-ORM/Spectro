import Foundation
@preconcurrency import PostgresNIO

/// Generic schema mapper that converts between database rows and Swift types
public struct SchemaMapper {

    public static func mapRow<T: Schema>(
        _ row: PostgresRow,
        to schemaType: T.Type,
        metadata: SchemaMetadata
    ) throws -> T {
        var instance = T()
        let randomAccess = row.makeRandomAccess()
        var values: [String: Any] = [:]

        for field in metadata.fields {
            let dbValue = randomAccess[data: field.databaseName]
            if let value = extractValue(from: dbValue, expectedType: field.type) {
                values[field.name] = value
            }
        }

        try applyValues(values, to: &instance, using: metadata)
        return instance
    }

    public static func extractData<T: Schema>(
        from instance: T,
        metadata: SchemaMetadata,
        excludePrimaryKey: Bool = false
    ) -> [String: PostgresData] {
        var data: [String: PostgresData] = [:]
        let mirror = Mirror(reflecting: instance)

        for child in mirror.children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard let field = metadata.fields.first(where: { $0.name == fieldName }) else { continue }
            if excludePrimaryKey && field.name == metadata.primaryKeyField { continue }

            if let value = extractPropertyWrapperValue(child.value),
               let postgresData = try? convertToPostgresData(value) {
                data[field.databaseName] = postgresData
            }
        }

        return data
    }

    // MARK: - Value Extraction

    public static func extractValue(from dbValue: PostgresData, expectedType: Any.Type) -> Any? {
        switch expectedType {
        case is String.Type: return dbValue.string
        case is Int.Type:    return dbValue.int
        case is Bool.Type:   return dbValue.bool
        case is UUID.Type:   return dbValue.uuid
        case is Date.Type:   return dbValue.date
        case is Double.Type: return dbValue.double
        case is Float.Type:  return dbValue.float
        case is Data.Type:
            if let bytes = dbValue.bytes { return Data(bytes) }
            return nil
        default: return nil
        }
    }

    private static func applyValues<T: Schema>(
        _ values: [String: Any],
        to instance: inout T,
        using metadata: SchemaMetadata
    ) throws {
        if var mutable = instance as? MutableSchema {
            mutable.apply(values: values)
            guard let result = mutable as? T else {
                throw SpectroError.invalidSchema(
                    reason: "MutableSchema.apply(values:) returned incompatible type for \(T.self)"
                )
            }
            instance = result
        } else {
            throw SpectroError.notImplemented(
                "Schema \(T.self) must implement SchemaBuilder or MutableSchema for row mapping"
            )
        }
    }

    private static func extractPropertyWrapperValue(_ wrapper: Any) -> Any? {
        let mirror = Mirror(reflecting: wrapper)
        for child in mirror.children {
            if child.label == "wrappedValue" { return child.value }
        }
        return wrapper
    }

    public static func convertToPostgresData(_ value: Any) throws -> PostgresData {
        // Handle nil optionals explicitly — send SQL NULL instead of throwing.
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional && mirror.children.isEmpty {
            return PostgresData(type: .null, value: nil)
        }

        switch value {
        case let v as String:  return PostgresData(string: v)
        case let v as Int:     return PostgresData(int: v)
        case let v as Bool:    return PostgresData(bool: v)
        case let v as UUID:    return PostgresData(uuid: v)
        case let v as Date:    return PostgresData(date: v)
        case let v as Double:  return PostgresData(double: v)
        case let v as Float:   return PostgresData(float: v)
        case let v as Data:    return PostgresData(bytes: [UInt8](v))
        default:
            throw SpectroError.invalidParameter(
                name: "value",
                value: String(describing: value),
                reason: "Unsupported type for PostgreSQL parameter: \(type(of: value))"
            )
        }
    }
}

// MARK: - MutableSchema

public protocol MutableSchema {
    mutating func apply(values: [String: Any])
}
