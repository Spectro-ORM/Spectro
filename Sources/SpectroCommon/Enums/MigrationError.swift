import Foundation

/// SQL migration file and session-lock errors.
public enum MigrationError: Error, LocalizedError {
    case fileExists(String)
    case invalidMigrationName(String)
    case invalidMigrationMissingTimestamp
    case directoryNotFound(String)
    case invalidMigrationFile(String)
    case lockTimeout

    public var errorDescription: String? {
        switch self {
        case .fileExists(let path): return "Migration file already exists: \(path)"
        case .invalidMigrationName(let name): return "Invalid migration name: \(name)"
        case .invalidMigrationMissingTimestamp: return "Migration filename is missing a timestamp"
        case .directoryNotFound(let path): return "Migration directory not found: \(path)"
        case .invalidMigrationFile(let path): return "Invalid migration file: \(path)"
        case .lockTimeout: return "Timed out waiting for the Spectro migration lock. Another migration runner may be active."
        }
    }
}
