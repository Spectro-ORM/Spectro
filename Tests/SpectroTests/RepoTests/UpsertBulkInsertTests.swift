import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Upsert and Bulk Insert")
struct UpsertBulkInsertTests {

    // MARK: - Table Setup

    /// Creates test_users table with a UNIQUE constraint on email for upsert testing.
    private func withUpsertTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "test_users" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL DEFAULT '',
                "email" TEXT NOT NULL DEFAULT '',
                "age" INT NOT NULL DEFAULT 0,
                "is_active" BOOLEAN NOT NULL DEFAULT true,
                "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)
        // Add unique constraint on email if it doesn't already exist
        try await repo.executeRawSQL("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'test_users_email_unique'
                ) THEN
                    ALTER TABLE "test_users" ADD CONSTRAINT "test_users_email_unique" UNIQUE ("email");
                END IF;
            END
            $$;
        """)
        try await repo.executeRawSQL("TRUNCATE \"test_users\"")
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    // MARK: - Upsert Tests

    @Test("Upsert inserts a new row when no conflict exists")
    func testUpsertInsertsNewRow() async throws {
        try await withUpsertTable { repo in
            let user = TestUser(name: "Alice", email: "alice@test.com", age: 30)
            let result = try await repo.upsert(
                user,
                conflictTarget: .columns(["email"]),
                set: nil
            )

            #expect(result.name == "Alice")
            #expect(result.email == "alice@test.com")
            #expect(result.age == 30)

            // Verify exactly one row exists
            let all = try await repo.all(TestUser.self)
            #expect(all.count == 1)
        }
    }

    @Test("Upsert updates existing row on conflict")
    func testUpsertUpdatesOnConflict() async throws {
        try await withUpsertTable { repo in
            // Insert the original record
            let original = try await repo.insert(
                TestUser(name: "Alice", email: "alice@test.com", age: 30)
            )

            // Upsert with the same email but different name and age
            let upserted = try await repo.upsert(
                TestUser(name: "Alicia Updated", email: "alice@test.com", age: 31),
                conflictTarget: .columns(["email"]),
                set: nil
            )

            // The row should have been updated, not duplicated
            #expect(upserted.email == "alice@test.com")
            #expect(upserted.name == "Alicia Updated")
            #expect(upserted.age == 31)

            // Verify still exactly one row
            let all = try await repo.all(TestUser.self)
            #expect(all.count == 1)

            // Verify the ID from the original insert is preserved
            // (ON CONFLICT UPDATE keeps the existing row's primary key)
            #expect(all.first?.id == original.id)
        }
    }

    @Test("Upsert with selective column update only updates specified columns")
    func testUpsertSelectiveColumnUpdate() async throws {
        try await withUpsertTable { repo in
            // Insert the original record
            let _ = try await repo.insert(
                TestUser(name: "Alice", email: "alice@test.com", age: 30)
            )

            // Upsert with same email, but only update "name" — age should stay 30
            let upserted = try await repo.upsert(
                TestUser(name: "Alicia", email: "alice@test.com", age: 99),
                conflictTarget: .columns(["email"]),
                set: ["name"]
            )

            #expect(upserted.email == "alice@test.com")
            #expect(upserted.name == "Alicia")
            // Age should NOT have been updated because we only specified "name" in `set`
            #expect(upserted.age == 30)

            // Verify still exactly one row
            let all = try await repo.all(TestUser.self)
            #expect(all.count == 1)
        }
    }

    // MARK: - Constraint Conflict Target Tests

    @Test("Upsert with .constraint() inserts new row when no conflict exists")
    func testConstraintUpsertInsertsNewRow() async throws {
        try await withUpsertTable { repo in
            let user = TestUser(name: "Alice", email: "alice@test.com", age: 30)
            let result = try await repo.upsert(
                user,
                conflictTarget: .constraint("test_users_email_unique"),
                set: nil
            )

            #expect(result.name == "Alice")
            #expect(result.email == "alice@test.com")
            #expect(result.age == 30)

            let all = try await repo.all(TestUser.self)
            #expect(all.count == 1)
        }
    }

    @Test("Upsert with .constraint() updates existing row on conflict")
    func testConstraintUpsertUpdatesOnConflict() async throws {
        try await withUpsertTable { repo in
            let original = try await repo.insert(
                TestUser(name: "Alice", email: "alice@test.com", age: 30)
            )

            let upserted = try await repo.upsert(
                TestUser(name: "Alicia Updated", email: "alice@test.com", age: 31),
                conflictTarget: .constraint("test_users_email_unique"),
                set: nil
            )

            #expect(upserted.email == "alice@test.com")
            #expect(upserted.name == "Alicia Updated")
            #expect(upserted.age == 31)

            let all = try await repo.all(TestUser.self)
            #expect(all.count == 1)
            #expect(all.first?.id == original.id)
        }
    }

    @Test("Upsert with .constraint() and selective set only updates specified columns")
    func testConstraintUpsertSelectiveSet() async throws {
        try await withUpsertTable { repo in
            let _ = try await repo.insert(
                TestUser(name: "Alice", email: "alice@test.com", age: 30)
            )

            let upserted = try await repo.upsert(
                TestUser(name: "Alicia", email: "alice@test.com", age: 99),
                conflictTarget: .constraint("test_users_email_unique"),
                set: ["name"]
            )

            #expect(upserted.email == "alice@test.com")
            #expect(upserted.name == "Alicia")
            #expect(upserted.age == 30)

            let all = try await repo.all(TestUser.self)
            #expect(all.count == 1)
        }
    }

    @Test("Upsert with empty set array throws invalidSchema")
    func testUpsertEmptySetThrows() async throws {
        try await withUpsertTable { repo in
            let user = TestUser(name: "Alice", email: "alice@test.com", age: 30)
            do {
                let _ = try await repo.upsert(
                    user,
                    conflictTarget: .constraint("test_users_email_unique"),
                    set: []
                )
                Issue.record("Expected SpectroError.invalidSchema to be thrown")
            } catch is SpectroError {
                // Expected
            }
        }
    }

    // MARK: - Bulk Insert Tests

    @Test("insertAll with empty array returns empty array")
    func testInsertAllEmptyArray() async throws {
        try await withUpsertTable { repo in
            let results = try await repo.insertAll([TestUser]())
            #expect(results.isEmpty)

            // Verify no rows were created
            let all = try await repo.all(TestUser.self)
            #expect(all.isEmpty)
        }
    }

    @Test("insertAll with a single item works")
    func testInsertAllSingleItem() async throws {
        try await withUpsertTable { repo in
            let users = [TestUser(name: "Alice", email: "alice@test.com", age: 30)]
            let results = try await repo.insertAll(users)

            #expect(results.count == 1)
            #expect(results[0].name == "Alice")
            #expect(results[0].email == "alice@test.com")
            #expect(results[0].age == 30)
        }
    }

    @Test("insertAll with multiple items returns all of them")
    func testInsertAllMultipleItems() async throws {
        try await withUpsertTable { repo in
            let users = [
                TestUser(name: "Alice", email: "alice@test.com", age: 30),
                TestUser(name: "Bob", email: "bob@test.com", age: 25),
                TestUser(name: "Charlie", email: "charlie@test.com", age: 35),
            ]
            let results = try await repo.insertAll(users)

            #expect(results.count == 3)

            // Verify all rows exist in the database
            let all = try await repo.all(TestUser.self)
            #expect(all.count == 3)
        }
    }

    @Test("insertAll preserves all field values correctly")
    func testInsertAllPreservesData() async throws {
        try await withUpsertTable { repo in
            let users = [
                TestUser(name: "Alice", email: "alice@test.com", age: 30, isActive: true),
                TestUser(name: "Bob", email: "bob@test.com", age: 25, isActive: false),
                TestUser(name: "Charlie", email: "charlie@test.com", age: 35, isActive: true),
            ]
            let results = try await repo.insertAll(users)

            #expect(results.count == 3)

            // Sort by name to have deterministic ordering for assertions
            let sorted = results.sorted { $0.name < $1.name }

            #expect(sorted[0].name == "Alice")
            #expect(sorted[0].email == "alice@test.com")
            #expect(sorted[0].age == 30)
            #expect(sorted[0].isActive == true)

            #expect(sorted[1].name == "Bob")
            #expect(sorted[1].email == "bob@test.com")
            #expect(sorted[1].age == 25)
            #expect(sorted[1].isActive == false)

            #expect(sorted[2].name == "Charlie")
            #expect(sorted[2].email == "charlie@test.com")
            #expect(sorted[2].age == 35)
            #expect(sorted[2].isActive == true)
        }
    }
}
}
