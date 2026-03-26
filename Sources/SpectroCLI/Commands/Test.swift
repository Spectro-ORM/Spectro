import ArgumentParser
@preconcurrency import Noora
import SpectroCommon

struct Test: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test"
    )

    @Argument(help: "String to convert")
    var input: String

    func run() throws {
        let headers: [TableCellStyle] = [.primary("Format"), .primary("Result")]
        let rows: [StyledTableRow] = [
            [.plain("Original"), .plain(input)],
            [.plain("Snake case"), .muted(input.snakeCase())],
            [.plain("Pascal case"), .muted(input.pascalCase())],
        ]
        SpectroUI.noora.table(headers: headers, rows: rows)
    }
}
