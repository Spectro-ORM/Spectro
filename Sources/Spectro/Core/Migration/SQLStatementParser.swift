import Foundation

enum SQLParsingError: Error {
    case unbalancedDollarQuotes
    case unterminatedQuote
    case unterminatedComment
}

/// Splits PostgreSQL statements, retaining quoted text and treating comments as whitespace.
enum SQLStatementParser {
    static func parse(_ sql: String) throws -> [String] {
        let chars = Array(sql.unicodeScalars)
        var statements: [String] = []
        var current = ""
        var i = 0
        var quote: Unicode.Scalar?
        var escapeString = false
        var dollarTag: [Unicode.Scalar] = []
        var commentDepth = 0

        func identifierStart(_ c: Unicode.Scalar) -> Bool { c == "_" || c.properties.isAlphabetic }
        func identifierPart(_ c: Unicode.Scalar) -> Bool {
            identifierStart(c) || c.properties.numericType != nil || c == "$"
        }
        func finish() {
            let statement = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !statement.isEmpty { statements.append(statement + ";") }
            current = ""
        }

        while i < chars.count {
            let c = chars[i]
            let next: Unicode.Scalar? = i + 1 < chars.count ? chars[i + 1] : nil
            if commentDepth > 0 {
                if c == "/", next == "*" { commentDepth += 1; i += 2 }
                else if c == "*", next == "/" { commentDepth -= 1; i += 2 }
                else { i += 1 }
                continue
            }
            if !dollarTag.isEmpty {
                if chars[i...].starts(with: dollarTag) {
                    current.unicodeScalars.append(contentsOf: dollarTag)
                    i += dollarTag.count
                    dollarTag = []
                } else {
                    current.unicodeScalars.append(c)
                    i += 1
                }
                continue
            }
            if let activeQuote = quote {
                current.unicodeScalars.append(c)
                i += 1
                if escapeString, c == "\\", let next {
                    current.unicodeScalars.append(next)
                    i += 1
                } else if c == activeQuote {
                    if next == activeQuote {
                        current.unicodeScalars.append(activeQuote)
                        i += 1
                    } else {
                        quote = nil
                        escapeString = false
                    }
                }
                continue
            }
            if c == "/", next == "*" {
                current += " "
                commentDepth = 1
                i += 2
                continue
            }
            if c == "-", next == "-" {
                current += " "
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "'" {
                quote = c
                escapeString = i > 0 && (chars[i - 1] == "e" || chars[i - 1] == "E")
                    && (i < 2 || !identifierPart(chars[i - 2]))
            } else if c == "\"" {
                quote = c
            } else if c == "$", i == 0 || !identifierPart(chars[i - 1]) {
                var end = i + 1
                if end < chars.count, chars[end] != "$", identifierStart(chars[end]) {
                    end += 1
                    while end < chars.count, identifierPart(chars[end]), chars[end] != "$" { end += 1 }
                }
                if end < chars.count, chars[end] == "$" {
                    dollarTag = Array(chars[i...end])
                    current.unicodeScalars.append(contentsOf: dollarTag)
                    i = end + 1
                    continue
                }
            } else if c == ";" {
                finish()
                i += 1
                continue
            }
            current.unicodeScalars.append(c)
            i += 1
        }
        if !dollarTag.isEmpty { throw SQLParsingError.unbalancedDollarQuotes }
        if quote != nil { throw SQLParsingError.unterminatedQuote }
        if commentDepth != 0 { throw SQLParsingError.unterminatedComment }
        finish()
        return statements
    }
}
