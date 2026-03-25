import Foundation
import Testing
@testable import Spectro
@testable import SpectroCommon

@Suite("SQL Statement Parser")
struct SQLStatementParserTests {

    @Test("Parses simple semicolon-separated statements")
    func simpleParsing() throws {
        let sql = """
        CREATE TABLE users (id SERIAL);
        INSERT INTO users DEFAULT VALUES;
        """

        let statements = try SQLStatementParser.parse(sql)
        #expect(statements.count == 2)
        #expect(statements[0].contains("CREATE TABLE"))
        #expect(statements[1].contains("INSERT INTO"))
    }

    @Test("Preserves dollar-quoted function bodies")
    func complexFunctionParsing() throws {
        let sql = """
        CREATE OR REPLACE FUNCTION update_timestamp()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ language 'plpgsql';
        """

        let statements = try SQLStatementParser.parse(sql)
        #expect(statements.count == 1)
        #expect(statements[0].contains("CREATE OR REPLACE FUNCTION"))
        #expect(statements[0].contains("RETURN NEW;"))
    }

    @Test("Handles mixed regular and dollar-quoted statements")
    func mixedStatements() throws {
        let sql = """
        CREATE TABLE test (id SERIAL);
        CREATE OR REPLACE FUNCTION test_func()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ language 'plpgsql';
        CREATE TRIGGER update_trigger BEFORE UPDATE ON test FOR EACH ROW EXECUTE FUNCTION test_func();
        """

        let statements = try SQLStatementParser.parse(sql)
        #expect(statements.count == 3)
    }

    @Test("Empty input returns no statements")
    func emptyInput() throws {
        let statements = try SQLStatementParser.parse("")
        #expect(statements.isEmpty)
    }

    @Test("Whitespace-only input returns no statements")
    func whitespaceOnly() throws {
        let statements = try SQLStatementParser.parse("   \n\t  ")
        #expect(statements.isEmpty)
    }
}
