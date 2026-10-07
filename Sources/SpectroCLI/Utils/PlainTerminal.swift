#if !RichTerminal
import Foundation

// Plain-text stand-ins for the Noora API the spectro command uses. Builds without the
// `RichTerminal` trait use them, for example when `roost spectro` runs an app's spectro.

struct TerminalText: ExpressibleByStringInterpolation, Sendable {
    enum Component { case command(String), primary(String), muted(String), accent(String), danger(String), success(String) }

    struct StringInterpolation: StringInterpolationProtocol {
        var text = ""
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { text += literal }
        mutating func appendInterpolation(_ value: some CustomStringConvertible) { text += value.description }
        mutating func appendInterpolation(_ component: Component) {
            switch component {
            case .command(let command): text += "`\(command)`"
            case .primary(let value), .muted(let value), .accent(let value), .danger(let value), .success(let value):
                text += value
            }
        }
    }

    let text: String
    init(stringLiteral value: String) { text = value }
    init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }
}

struct Alert: Sendable {
    let message: TerminalText
    let takeaways: [TerminalText]

    static func alert(_ message: TerminalText, takeaways: [TerminalText] = []) -> Alert {
        Alert(message: message, takeaways: takeaways)
    }

    static func alert(_ message: TerminalText, takeaway: TerminalText) -> Alert {
        Alert(message: message, takeaways: [takeaway])
    }
}

enum TableCellStyle: Sendable {
    case plain(String), primary(String), muted(String), success(String), warning(String), danger(String)

    var text: String {
        switch self {
        case .plain(let value), .primary(let value), .muted(let value), .success(let value), .warning(let value), .danger(let value):
            value
        }
    }
}

typealias StyledTableRow = [TableCellStyle]

struct PlainTerminal: Sendable {
    func success(_ alert: Alert) { show("✓", alert) }
    func info(_ alert: Alert) { show("•", alert) }
    func warning(_ alert: Alert) { show("!", alert) }
    func error(_ alert: Alert) { show("✗", alert, error: true) }

    func progressStep(message: String, successMessage: String?, errorMessage: String?, showSpinner: Bool,
                      task: ((String) -> Void) async throws -> Void) async throws {
        print("\(message)…")
        do {
            try await task { print("  \($0)") }
        } catch {
            if let errorMessage { write("✗ \(errorMessage)\n", error: true) }
            throw error
        }
        if let successMessage { print("✓ \(successMessage)") }
    }

    func yesOrNoChoicePrompt(title: TerminalText? = nil, question: TerminalText, defaultAnswer: Bool) -> Bool {
        print("\(question.text) [\(defaultAnswer ? "Y/n" : "y/N")] ", terminator: "")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), !answer.isEmpty else {
            return defaultAnswer
        }
        return answer.hasPrefix("y")
    }

    func table(headers: [TableCellStyle], rows: [StyledTableRow]) {
        let widths = headers.indices.map { column in
            ([headers] + rows).map { column < $0.count ? $0[column].text.count : 0 }.max() ?? 0
        }
        func line(_ cells: [TableCellStyle]) -> String {
            let padded = zip(cells, widths).map { $0.text.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: "  ")
            return String(padded.reversed().drop { $0 == " " }.reversed())
        }
        print(line(headers))
        print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        rows.forEach { print(line($0)) }
    }

    private func show(_ symbol: String, _ alert: Alert, error: Bool = false) {
        let takeaways = alert.takeaways.map { "  → \($0.text)\n" }.joined()
        write("\(symbol) \(alert.message.text)\n\(takeaways)", error: error)
    }

    private func write(_ text: String, error: Bool) {
        if error { FileHandle.standardError.write(Data(text.utf8)) } else { print(text, terminator: "") }
    }
}
#endif
