import Foundation

public extension String {
    /// Converts a camelCase string to snake_case.
    func snakeCase() -> String {
        let pattern = "([a-z0-9])([A-Z])"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
        }

        let range = NSRange(location: 0, length: count)
        let snakeCased = regex.stringByReplacingMatches(
            in: self,
            range: range,
            withTemplate: "$1_$2"
        ).lowercased()

        return snakeCased
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    func pascalCase() -> String {
        snakeCase().split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined()
    }

    /// Returns this string as a double-quoted PostgreSQL identifier.
    ///
    /// Any embedded double-quote characters are escaped by doubling them,
    /// per the SQL standard. This makes it safe to use reserved words
    /// (e.g. "user", "order") and mixed-case names as table or column identifiers.
    ///
    ///     "user".quoted       // → "\"user\""
    ///     "createdAt".quoted  // → "\"createdAt\""
    var quoted: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
