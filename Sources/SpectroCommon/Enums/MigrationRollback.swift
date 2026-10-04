public enum MigrationRollback: Sendable, Equatable {
    case sql(String)
    case irreversible(reason: String)
}

