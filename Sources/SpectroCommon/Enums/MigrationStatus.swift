/// Migration states represented by the shared PostgreSQL ledger.
public enum MigrationStatus: String, Sendable, CaseIterable {
    /// The migration has not completed or has been rolled back.
    case pending
    /// The migration's forward statements and ledger update committed.
    case completed
    /// A failure state retained in the ledger's vocabulary.
    case failed
}
