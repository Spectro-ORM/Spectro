/// Describes how a prepared migration rolls back, or why it cannot.
public enum MigrationRollback: Sendable, Equatable {
    /// SQL executed to reverse the migration within its transaction.
    case sql(String)
    /// A nonempty explanation that causes a selected rollback batch to fail preflight.
    case irreversible(reason: String)
}
