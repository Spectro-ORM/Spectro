import Foundation
import PostgresKit

public indirect enum ConditionValue: Sendable, Equatable, Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case uuid(UUID)
    case date(Date)
    case null
    case jsonb(String)
    case between(ConditionValue, ConditionValue)
    case array([ConditionValue])

    /// Convert an arbitrary `Any` value to a `ConditionValue`.
    ///
    /// Strings are always treated as plain `.string` values. To produce a
    /// `.jsonb` value, construct it explicitly: `ConditionValue.jsonb("{...}")`.
    public static func value(_ value: Any) -> ConditionValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let uuid as UUID:
            return .uuid(uuid)
        case let date as Date:
            return .date(date)
        case let array as [Any]:
            return .array(array.map { ConditionValue.value($0) })
        case is NSNull:
            return .null
        default:
            return .string(String(describing: value))
        }
    }

    func toPostgresData() throws -> PostgresData {
        switch self {
        case .string(let value):
            return PostgresData(string: value)
        case .int(let value):
            return PostgresData(int64: Int64(value))
        case .double(let value):
            return PostgresData(double: value)
        case .bool(let value):
            return PostgresData(bool: value)
        case .uuid(let value):
            return PostgresData(uuid: value)
        case .date(let value):
            return PostgresData(date: value)
        case .jsonb(let value):
            return try PostgresData(jsonb: value)
        case .between:
            throw SpectroError.invalidParameter(name: "between", value: nil, reason: "BETWEEN conditions should be handled by SQLBuilder")
        case .array:
            throw SpectroError.invalidParameter(name: "array", value: nil, reason: "Array conditions should be handled by SQLBuilder")
        case .null:
            return PostgresData(type: .null, value: nil)
        }
    }
}

// MARK: - Literal Conformances

extension ConditionValue: ExpressibleByStringLiteral {
    /// String literals always produce `.string`. Use `.jsonb("...")` explicitly for JSONB values.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension ConditionValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension ConditionValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension ConditionValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension ConditionValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
