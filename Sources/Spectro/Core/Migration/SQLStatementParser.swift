import Foundation

enum SQLParsingError: Error {
    case unbalancedDollarQuotes
}

/// Splits a SQL string into individual statements at semicolons, correctly
/// handling PostgreSQL dollar-quoted strings, single-quoted strings,
/// full-line `--` comments, inline `--` comments, and `/* */` block comments.
enum SQLStatementParser {

    static func parse(_ sql: String) throws -> [String] {
        var statements: [String] = []
        var current = ""
        var inDollarQuote = false
        var dollarTag = ""
        var inSingleQuote = false
        var inBlockComment = false

        var chars = Array(sql.unicodeScalars)
        var i = chars.startIndex

        while i < chars.endIndex {
            let c = chars[i]

            // ── Block comments /* ... */ ────────────────────────────────────
            if inBlockComment {
                if c == "*", let next = chars.index(i, offsetBy: 1, limitedBy: chars.endIndex),
                   next < chars.endIndex, chars[next] == "/" {
                    inBlockComment = false
                    i = chars.index(i, offsetBy: 2)
                    continue
                }
                i = chars.index(after: i)
                continue
            }

            // ── Single-quoted strings 'text' ────────────────────────────────
            if inSingleQuote {
                if c == "'" {
                    inSingleQuote = false
                    current.unicodeScalars.append(c)
                } else {
                    current.unicodeScalars.append(c)
                }
                i = chars.index(after: i)
                continue
            }

            // ── Dollar-quoted strings $$body$$ ──────────────────────────────
            if inDollarQuote {
                // Check if we've hit the closing tag
                let remaining = chars[i...]
                let tagScalars = Array(dollarTag.unicodeScalars)
                if remaining.count >= tagScalars.count &&
                   Array(remaining.prefix(tagScalars.count)) == tagScalars {
                    current += dollarTag
                    inDollarQuote = false
                    dollarTag = ""
                    i = chars.index(i, offsetBy: tagScalars.count)
                    continue
                }
                current.unicodeScalars.append(c)
                i = chars.index(after: i)
                continue
            }

            // ── Detect opening of block comment /* ──────────────────────────
            if c == "/", let next = chars.index(i, offsetBy: 1, limitedBy: chars.endIndex),
               next < chars.endIndex, chars[next] == "*" {
                inBlockComment = true
                i = chars.index(i, offsetBy: 2)
                continue
            }

            // ── Detect inline -- comment (skip to end of line) ──────────────
            if c == "-", let next = chars.index(i, offsetBy: 1, limitedBy: chars.endIndex),
               next < chars.endIndex, chars[next] == "-" {
                // Skip until newline
                while i < chars.endIndex && chars[i] != "\n" {
                    i = chars.index(after: i)
                }
                continue
            }

            // ── Detect opening dollar quote ─────────────────────────────────
            if c == "$" {
                var tag = "$"
                var j = chars.index(after: i)
                while j < chars.endIndex && chars[j] != "$" {
                    tag.unicodeScalars.append(chars[j])
                    j = chars.index(after: j)
                }
                if j < chars.endIndex && chars[j] == "$" {
                    tag.append("$")
                    dollarTag = tag
                    inDollarQuote = true
                    current += tag
                    i = chars.index(after: j)
                    continue
                }
                // Not a dollar quote — treat as regular character
                current.unicodeScalars.append(c)
                i = chars.index(after: i)
                continue
            }

            // ── Single-quote start ──────────────────────────────────────────
            if c == "'" {
                inSingleQuote = true
                current.unicodeScalars.append(c)
                i = chars.index(after: i)
                continue
            }

            // ── Semicolon — end of statement ────────────────────────────────
            if c == ";" {
                let stmt = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stmt.isEmpty {
                    statements.append(stmt + ";")
                }
                current = ""
                i = chars.index(after: i)
                continue
            }

            current.unicodeScalars.append(c)
            i = chars.index(after: i)
        }

        // Any remaining content (statement without trailing semicolon)
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            statements.append(tail.hasSuffix(";") ? tail : tail + ";")
        }

        if inDollarQuote {
            throw SQLParsingError.unbalancedDollarQuotes
        }

        return statements
    }
}
