/// Represents a single row from a grouped aggregate query.
///
/// `group` maps each GROUP BY column name to its value (as a string).
/// `value` holds the aggregate result (e.g., SUM, AVG) for that group.
public struct GroupedResult: Sendable {
    public let group: [String: String]
    public let value: Double?
}
