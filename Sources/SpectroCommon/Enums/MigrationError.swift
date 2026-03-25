public enum MigrationError: Error {
    case fileExists(String)
    case invalidMigrationName(String)
    case invalidMigrationMissingTimestamp
    case directoryNotFound(String)
    case invalidMigrationFile(String)
}
