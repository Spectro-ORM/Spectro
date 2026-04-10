import Foundation
import Testing
@testable import Spectro

@Suite("Changeset")
struct ChangesetTests {

    // MARK: - Cast

    @Test("cast filters to permitted fields only")
    func castPermitted() {
        let cs = Changeset<TestUser>.cast(
            nil,
            params: ["name": "Alice", "email": "a@b.com", "age": 30, "admin": true],
            permitted: ["name", "email", "age"]
        )
        #expect(cs.changes.count == 3)
        #expect(cs.getChange("name") as? String == "Alice")
        #expect(cs.getChange("email") as? String == "a@b.com")
        #expect(cs.getChange("age") as? Int == 30)
        #expect(cs.getChange("admin") == nil)
    }

    @Test("cast with nil data sets insert action")
    func castInsertAction() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
        #expect(cs.action == .insert)
        #expect(cs.data == nil)
    }

    @Test("cast with existing data sets update action")
    func castUpdateAction() {
        let user = TestUser(name: "Alice", email: "a@b.com", age: 25)
        let cs = Changeset<TestUser>.cast(user, params: ["name": "Bob"], permitted: ["name"])
        #expect(cs.action == .update)
        #expect(cs.data != nil)
    }

    @Test("cast with empty params produces empty changes")
    func castEmpty() {
        let cs = Changeset<TestUser>.cast(nil, params: [:], permitted: ["name"])
        #expect(cs.changes.isEmpty)
        #expect(cs.isValid)
    }

    // MARK: - Field Access

    @Test("getField returns change when present")
    func getFieldFromChange() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
        #expect(cs.getField("name") as? String == "Alice")
    }

    @Test("getField falls back to data when no change")
    func getFieldFromData() {
        let user = TestUser(name: "Alice", email: "a@b.com", age: 25)
        let cs = Changeset<TestUser>.cast(user, params: [:], permitted: ["name"])
        #expect(cs.getField("name") as? String == "Alice")
        #expect(cs.getField("email") as? String == "a@b.com")
    }

    @Test("getField returns nil for unknown field with no data")
    func getFieldUnknown() {
        let cs = Changeset<TestUser>.cast(nil, params: [:], permitted: [])
        #expect(cs.getField("nonexistent") == nil)
    }

    // MARK: - putChange / deleteChange

    @Test("putChange adds or replaces a change")
    func putChange() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .putChange("name", value: "Bob")
            .putChange("email", value: "bob@example.com")
        #expect(cs.getChange("name") as? String == "Bob")
        #expect(cs.getChange("email") as? String == "bob@example.com")
    }

    @Test("deleteChange removes a change")
    func deleteChange() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .deleteChange("name")
        #expect(cs.getChange("name") == nil)
    }

    // MARK: - validateRequired

    @Test("validateRequired passes when fields have values")
    func requiredValid() {
        let cs = Changeset<TestUser>.cast(
            nil,
            params: ["name": "Alice", "email": "a@b.com"],
            permitted: ["name", "email"]
        ).validateRequired(["name", "email"])

        #expect(cs.isValid)
        #expect(cs.errors.isEmpty)
    }

    @Test("validateRequired fails for missing fields")
    func requiredMissing() {
        let cs = Changeset<TestUser>.cast(
            nil,
            params: ["name": "Alice"],
            permitted: ["name", "email"]
        ).validateRequired(["name", "email"])

        #expect(!cs.isValid)
        #expect(cs.errors["email"]?.first == "can't be blank")
        #expect(cs.errors["name"] == nil)
    }

    @Test("validateRequired fails when field not in changes or data")
    func requiredMissingField() {
        // bio is permitted but not provided in params, and data is nil
        let cs = Changeset<TestUserWithBio>.cast(
            nil,
            params: ["name": "Alice", "email": "a@b.com"],
            permitted: ["name", "email", "bio"]
        ).validateRequired(["bio"])

        #expect(!cs.isValid)
        #expect(cs.errors["bio"]?.first == "can't be blank")
    }

    @Test("validateRequired rejects empty strings")
    func requiredEmptyString() {
        let cs = Changeset<TestUser>.cast(
            nil,
            params: ["name": "", "email": "   "],
            permitted: ["name", "email"]
        ).validateRequired(["name", "email"])

        #expect(!cs.isValid)
        #expect(cs.errors["name"]?.first == "can't be blank")
        #expect(cs.errors["email"]?.first == "can't be blank")
    }

    @Test("validateRequired uses data fallback")
    func requiredFromData() {
        let user = TestUser(name: "Alice", email: "a@b.com", age: 25)
        let cs = Changeset<TestUser>.cast(
            user,
            params: [:],
            permitted: ["name"]
        ).validateRequired(["name"])

        #expect(cs.isValid)
    }

    // MARK: - validateLength

    @Test("validateLength min passes for long enough string")
    func lengthMinValid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .validateLength("name", min: 2)
        #expect(cs.isValid)
    }

    @Test("validateLength min fails for short string")
    func lengthMinInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "A"], permitted: ["name"])
            .validateLength("name", min: 2)
        #expect(!cs.isValid)
        #expect(cs.errors["name"]?.first == "should be at least 2 character(s)")
    }

    @Test("validateLength max fails for long string")
    func lengthMaxInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "A very long name indeed"], permitted: ["name"])
            .validateLength("name", max: 10)
        #expect(!cs.isValid)
        #expect(cs.errors["name"]?.first == "should be at most 10 character(s)")
    }

    @Test("validateLength exact match")
    func lengthExact() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .validateLength("name", is: 5)
        #expect(cs.isValid)

        let cs2 = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .validateLength("name", is: 3)
        #expect(!cs2.isValid)
        #expect(cs2.errors["name"]?.first == "should be 3 character(s)")
    }

    @Test("validateLength skips non-string fields")
    func lengthNonString() {
        let cs = Changeset<TestUser>.cast(nil, params: ["age": 25], permitted: ["age"])
            .validateLength("age", min: 1)
        #expect(cs.isValid)
    }

    @Test("validateLength skips missing fields")
    func lengthMissing() {
        let cs = Changeset<TestUser>.cast(nil, params: [:], permitted: ["name"])
            .validateLength("name", min: 1)
        #expect(cs.isValid)
    }

    // MARK: - validateFormat

    @Test("validateFormat passes for matching pattern")
    func formatValid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["email": "alice@example.com"], permitted: ["email"])
            .validateFormat("email", pattern: "^.+@.+\\..+$")
        #expect(cs.isValid)
    }

    @Test("validateFormat fails for non-matching pattern")
    func formatInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["email": "not-an-email"], permitted: ["email"])
            .validateFormat("email", pattern: "^.+@.+\\..+$")
        #expect(!cs.isValid)
        #expect(cs.errors["email"]?.first == "has invalid format")
    }

    @Test("validateFormat with custom message")
    func formatCustomMessage() {
        let cs = Changeset<TestUser>.cast(nil, params: ["email": "bad"], permitted: ["email"])
            .validateFormat("email", pattern: "^.+@.+$", message: "must be a valid email")
        #expect(cs.errors["email"]?.first == "must be a valid email")
    }

    // MARK: - validateInclusion

    @Test("validateInclusion passes for included value")
    func inclusionValid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .validateInclusion("name", in: ["Alice", "Bob", "Charlie"])
        #expect(cs.isValid)
    }

    @Test("validateInclusion fails for excluded value")
    func inclusionInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Dave"], permitted: ["name"])
            .validateInclusion("name", in: ["Alice", "Bob", "Charlie"])
        #expect(!cs.isValid)
        #expect(cs.errors["name"]?.first == "is invalid")
    }

    // MARK: - validateExclusion

    @Test("validateExclusion passes for non-reserved value")
    func exclusionValid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .validateExclusion("name", in: ["admin", "root", "system"])
        #expect(cs.isValid)
    }

    @Test("validateExclusion fails for reserved value")
    func exclusionInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "admin"], permitted: ["name"])
            .validateExclusion("name", in: ["admin", "root", "system"])
        #expect(!cs.isValid)
        #expect(cs.errors["name"]?.first == "is reserved")
    }

    // MARK: - validateNumber

    @Test("validateNumber greaterThan passes")
    func numberGTValid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["age": 25], permitted: ["age"])
            .validateNumber("age", greaterThan: 18)
        #expect(cs.isValid)
    }

    @Test("validateNumber greaterThan fails")
    func numberGTInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["age": 15], permitted: ["age"])
            .validateNumber("age", greaterThan: 18)
        #expect(!cs.isValid)
        #expect(cs.errors["age"]?.first == "must be greater than 18.0")
    }

    @Test("validateNumber lessThan passes")
    func numberLTValid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["age": 25], permitted: ["age"])
            .validateNumber("age", lessThan: 100)
        #expect(cs.isValid)
    }

    @Test("validateNumber combined constraints")
    func numberCombined() {
        let cs = Changeset<TestUser>.cast(nil, params: ["age": 150], permitted: ["age"])
            .validateNumber("age", greaterThanOrEqualTo: 0, lessThanOrEqualTo: 120)
        #expect(!cs.isValid)
        #expect(cs.errors["age"]?.count == 1)
    }

    // MARK: - validateCustom

    @Test("validateCustom with passing check")
    func customValid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .validateCustom("name") { value in
                guard let str = value as? String else { return "not a string" }
                return str.first?.isUppercase == true ? nil : "must start with uppercase"
            }
        #expect(cs.isValid)
    }

    @Test("validateCustom with failing check")
    func customInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "alice"], permitted: ["name"])
            .validateCustom("name") { value in
                guard let str = value as? String else { return "not a string" }
                return str.first?.isUppercase == true ? nil : "must start with uppercase"
            }
        #expect(!cs.isValid)
        #expect(cs.errors["name"]?.first == "must start with uppercase")
    }

    // MARK: - addError

    @Test("addError marks changeset as invalid")
    func addError() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
            .addError("name", message: "already taken")
        #expect(!cs.isValid)
        #expect(cs.errors["name"]?.first == "already taken")
    }

    // MARK: - Pipeline

    @Test("full validation pipeline")
    func pipeline() {
        let cs = Changeset<TestUser>.cast(
            nil,
            params: ["name": "A", "email": "bad", "age": -5],
            permitted: ["name", "email", "age"]
        )
        .validateRequired(["name", "email", "age"])
        .validateLength("name", min: 2, max: 100)
        .validateFormat("email", pattern: "^.+@.+\\..+$")
        .validateNumber("age", greaterThanOrEqualTo: 0)

        #expect(!cs.isValid)
        #expect(cs.errors["name"] != nil)
        #expect(cs.errors["email"] != nil)
        #expect(cs.errors["age"] != nil)
    }

    @Test("valid pipeline produces no errors")
    func pipelineValid() {
        let cs = Changeset<TestUser>.cast(
            nil,
            params: ["name": "Alice", "email": "alice@example.com", "age": 25],
            permitted: ["name", "email", "age"]
        )
        .validateRequired(["name", "email", "age"])
        .validateLength("name", min: 2, max: 100)
        .validateFormat("email", pattern: "^.+@.+\\..+$")
        .validateNumber("age", greaterThanOrEqualTo: 0, lessThanOrEqualTo: 150)

        #expect(cs.isValid)
    }

    // MARK: - applyChanges

    @Test("applyChanges returns changes dict when valid")
    func applyChangesValid() throws {
        let cs = Changeset<TestUser>.cast(
            nil,
            params: ["name": "Alice", "email": "a@b.com"],
            permitted: ["name", "email"]
        )
        let changes = try cs.applyChanges()
        #expect(changes["name"] as? String == "Alice")
        #expect(changes["email"] as? String == "a@b.com")
    }

    @Test("applyChanges throws when invalid")
    func applyChangesInvalid() {
        let cs = Changeset<TestUser>.cast(nil, params: [:], permitted: ["name"])
            .validateRequired(["name"])
        #expect(throws: SpectroError.self) {
            _ = try cs.applyChanges()
        }
    }

    // MARK: - Value Type Semantics

    @Test("changeset is a value type — mutations don't affect copies")
    func valueTypeSemantics() {
        let cs1 = Changeset<TestUser>.cast(nil, params: ["name": "Alice"], permitted: ["name"])
        let cs2 = cs1.validateRequired(["email"])

        #expect(cs1.isValid)
        #expect(!cs2.isValid)
    }

    @Test("multiple errors accumulate on the same field")
    func multipleErrors() {
        let cs = Changeset<TestUser>.cast(nil, params: ["name": ""], permitted: ["name"])
            .addError("name", message: "can't be blank")
            .addError("name", message: "is too short")
        #expect(cs.errors["name"]?.count == 2)
    }
}
