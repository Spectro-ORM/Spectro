/// Specifies the target for ON CONFLICT clause in upsert operations.
public enum ConflictTarget: Sendable {
    /// Conflict on specific columns: ON CONFLICT (col1, col2)
    case columns([String])
    /// Conflict on a named constraint: ON CONFLICT ON CONSTRAINT name
    case constraint(String)
}
