import ArgumentParser
import Foundation
import PostgresKit

/// Validate a database identifier to prevent SQL injection.
/// PostgreSQL identifiers can't be parameterized, so we allowlist safe characters.
func validateDatabaseIdentifier(_ name: String) throws {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    guard !name.isEmpty,
          name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
          !name.first!.isNumber else {
        print("Error: Invalid database name '\(name)'. Use only letters, numbers, and underscores.")
        throw ExitCode.validationFailure
    }
}

/// Escape a PostgreSQL identifier by doubling embedded double-quotes.
func escapeIdentifier(_ name: String) -> String {
    name.replacingOccurrences(of: "\"", with: "\"\"")
}

/// Extract a human-readable message from a PostgreSQL error.
func extractPGMessage(from error: any Error) -> String {
    if let psql = error as? PSQLError,
       let message = psql.serverInfo?[.message] {
        return message
    }
    // Fall back to the error description without the full type name
    let desc = String(describing: error)
    // Strip "SpectroError.queryExecutionFailed(sql: ..., error: " wrapper
    if let range = desc.range(of: "server: ") {
        let start = range.upperBound
        let end = desc.index(before: desc.endIndex)
        return String(desc[start...end])
    }
    return desc
}
