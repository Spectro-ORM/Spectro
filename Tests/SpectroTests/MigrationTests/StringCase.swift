import Testing
@testable import SpectroCommon

@Suite("String Case Conversion")
struct StringCaseTests {

    @Test("snakeCase converts camelCase")
    func snakeCaseFromCamel() {
        #expect("createUsersTable".snakeCase() == "create_users_table")
    }

    @Test("snakeCase converts all-caps abbreviation")
    func snakeCaseAllCaps() {
        #expect("APIResponse".snakeCase() == "apiresponse")
    }

    @Test("snakeCase converts spaces")
    func snakeCaseFromSpaces() {
        #expect("Create Users Table".snakeCase() == "create_users_table")
    }

    @Test("snakeCase converts hyphens")
    func snakeCaseFromHyphens() {
        #expect("create-users-table".snakeCase() == "create_users_table")
    }

    @Test("snakeCase preserves already snake_case")
    func snakeCaseIdempotent() {
        #expect("already_snake_case".snakeCase() == "already_snake_case")
    }

    @Test("snakeCase handles mixed separators")
    func snakeCaseMixed() {
        #expect("CreateUsers-Table Space".snakeCase() == "create_users_table_space")
    }

    @Test("pascalCase from snake_case")
    func pascalCaseFromSnake() {
        #expect("create_users_table".pascalCase() == "CreateUsersTable")
    }

    @Test("pascalCase from spaces")
    func pascalCaseFromSpaces() {
        #expect("create users table".pascalCase() == "CreateUsersTable")
    }

    @Test("pascalCase from hyphens")
    func pascalCaseFromHyphens() {
        #expect("create-users-table".pascalCase() == "CreateUsersTable")
    }

    @Test("pascalCase preserves already PascalCase")
    func pascalCaseIdempotent() {
        #expect("CreateUsersTable".pascalCase() == "CreateUsersTable")
    }

    @Test("pascalCase handles mixed separators")
    func pascalCaseMixed() {
        #expect("create_Users-table SPACE".pascalCase() == "CreateUsersTableSpace")
    }
}
