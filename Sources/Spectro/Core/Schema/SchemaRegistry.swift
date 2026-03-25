import Foundation

// MARK: - FieldType
//
// Replaces Any.Type in FieldInfo. Using a closed enum instead of metatypes
// makes FieldInfo fully Sendable without @unchecked, and allows exhaustive
// switching in SchemaMapper without runtime reflection.

public enum FieldType: Sendable {
    case string
    case int
    case double
    case float
    case bool
    case uuid
    case date
}

// MARK: - FieldInfo

public struct FieldInfo: Sendable {
    public let name: String
    public let databaseName: String
    public let fieldType: FieldType
    public let isPrimaryKey: Bool
    public let isForeignKey: Bool
    public let isTimestamp: Bool
    public let isNullable: Bool

    /// The Swift metatype for this field, derived from `fieldType`.
    ///
    /// Provided for backward compatibility with `SchemaMapper.extractValue(from:expectedType:)`.
    /// Prefer `fieldType` for new code.
    public var type: Any.Type {
        switch fieldType {
        case .string: return String.self
        case .int: return Int.self
        case .double: return Double.self
        case .float: return Float.self
        case .bool: return Bool.self
        case .uuid: return UUID.self
        case .date: return Date.self
        }
    }
}

// MARK: - SchemaMetadata

public struct SchemaMetadata: Sendable {
    public let tableName: String
    public let fields: [FieldInfo]
    public let primaryKeyField: String?

    public init(tableName: String, fields: [FieldInfo]) {
        self.tableName = tableName
        self.fields = fields
        self.primaryKeyField = fields.first(where: { $0.isPrimaryKey })?.name
    }
}

// MARK: - SchemaRegistry

public actor SchemaRegistry {
    private var registry: [String: SchemaMetadata] = [:]

    public static let shared = SchemaRegistry()

    private init() {}

    public func register<T: Schema>(_ type: T.Type) -> SchemaMetadata {
        let typeName = String(describing: type)
        if let existing = registry[typeName] { return existing }
        let metadata = extractMetadata(from: type)
        registry[typeName] = metadata
        return metadata
    }

    public func metadata<T: Schema>(for type: T.Type) -> SchemaMetadata? {
        registry[String(describing: type)]
    }

    private func extractMetadata<T: Schema>(from type: T.Type) -> SchemaMetadata {
        let instance = T()
        let mirror = Mirror(reflecting: instance)
        let fields = mirror.children.compactMap { child -> FieldInfo? in
            guard let label = child.label else { return nil }
            return extractFieldInfo(label: label, value: child.value)
        }
        return SchemaMetadata(tableName: T.tableName, fields: fields)
    }

    private func extractFieldInfo(label: String, value: Any) -> FieldInfo? {
        let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
        let defaultDBName = fieldName.snakeCase()

        switch value {
        case let pk as any PrimaryKeyWrapperProtocol:
            return FieldInfo(name: fieldName, databaseName: defaultDBName, fieldType: pk.primaryKeyFieldType,
                             isPrimaryKey: true, isForeignKey: false, isTimestamp: false, isNullable: false)

        case let col as Column<String>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .string,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case let col as Column<String?>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .string,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case let col as Column<Int>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .int,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case let col as Column<Int?>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .int,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case let col as Column<Bool>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .bool,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case let col as Column<Bool?>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .bool,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case let col as Column<Double>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .double,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case let col as Column<Double?>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .double,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case let col as Column<Float>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .float,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case let col as Column<Float?>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .float,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case let col as Column<Date>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .date,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case let col as Column<Date?>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .date,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case let col as Column<UUID>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .uuid,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case let col as Column<UUID?>:
            return FieldInfo(name: fieldName, databaseName: col.columnName ?? defaultDBName, fieldType: .uuid,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Timestamp:
            return FieldInfo(name: fieldName, databaseName: defaultDBName, fieldType: .date,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: true, isNullable: false)

        case let col as any ForeignKeyWrapperProtocol:
            return FieldInfo(name: fieldName, databaseName: col.foreignKeyColumnName ?? defaultDBName, fieldType: col.foreignKeyFieldType,
                             isPrimaryKey: false, isForeignKey: true, isTimestamp: false, isNullable: false)

        default:
            return nil
        }
    }
}

// MARK: - Schema Extension

extension Schema {
    public static var metadata: SchemaMetadata {
        get async {
            await SchemaRegistry.shared.register(self)
        }
    }
}
