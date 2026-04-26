import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
    @Suite("Changeset Integration")
    struct ChangesetIntegrationTests {

        private func withCleanTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
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
            try await repo.executeRawSQL(#"TRUNCATE "test_users""#)
            do {
                try await body(repo)
            } catch {
                await spectro.shutdown()
                throw error
            }
            await spectro.shutdown()
        }

        @Test("Insert valid changeset persists record with correct values")
        func insertValidChangeset() async throws {
            try await withCleanTable { repo in
                let cs = Changeset<TestUser>.cast(nil, params: ["name": "Alice", "email": "alice@test.com", "age": 30], permitted: ["name", "email", "age"])
                    .validateRequired(["name", "email"])

                let user = try await repo.insert(cs)

                #expect(user.name == "Alice")
                #expect(user.email == "alice@test.com")
                #expect(user.age == 30)

                let fetched = try await repo.get(TestUser.self, id: user.id)
                #expect(fetched?.name == "Alice")
                #expect(fetched?.email == "alice@test.com")
            }
        }

        @Test("Insert invalid changeset throws before touching database")
        func insertInvalidChangesetThrows() async throws {
            try await withCleanTable { repo in
                let cs = Changeset<TestUser>.cast(nil, params: ["name": "", "email": "alice@test.com"], permitted: ["name", "email"])
                    .validateRequired(["name", "email"])

                do {
                    let _ = try await repo.insert(cs)
                    Issue.record("Expected validationError to be thrown")
                } catch is SpectroError {
                    // Expected
                }

                let all = try await repo.all(TestUser.self)
                #expect(all.isEmpty)
            }
        }

        @Test("Insert changeset with no changes throws invalidSchema")
        func insertEmptyChangesetThrows() async throws {
            try await withCleanTable { repo in
                let cs = Changeset<TestUser>.cast(nil, params: [:], permitted: ["name"])

                do {
                    let _ = try await repo.insert(cs)
                    Issue.record("Expected SpectroError to be thrown")
                } catch is SpectroError {
                    // Expected
                }
            }
        }

        @Test("Update valid changeset only persists changed fields")
        func updateValidChangeset() async throws {
            try await withCleanTable { repo in
                let original = try await repo.insert(TestUser(name: "Bob", email: "bob@test.com", age: 25))

                let cs = Changeset.cast(original, params: ["name": "Robert"], permitted: ["name"])
                    .validateRequired(["name"])
                    .validateLength("name", min: 2)

                let updated = try await repo.update(cs)

                #expect(updated.name == "Robert")
                #expect(updated.email == "bob@test.com")
                #expect(updated.age == 25)

                let fetched = try await repo.get(TestUser.self, id: original.id)
                #expect(fetched?.name == "Robert")
                #expect(fetched?.email == "bob@test.com")
            }
        }

        @Test("Update invalid changeset throws before touching database")
        func updateInvalidChangesetThrows() async throws {
            try await withCleanTable { repo in
                let original = try await repo.insert(TestUser(name: "Carol", email: "carol@test.com", age: 40))

                let cs = Changeset.cast(original, params: ["name": ""], permitted: ["name"])
                    .validateRequired(["name"])

                do {
                    let _ = try await repo.update(cs)
                    Issue.record("Expected validationError to be thrown")
                } catch is SpectroError {
                    // Expected
                }

                let fetched = try await repo.get(TestUser.self, id: original.id)
                #expect(fetched?.name == "Carol")
            }
        }

        @Test("Update changeset with no data throws invalidSchema")
        func updateChangesetWithNoDataThrows() async throws {
            try await withCleanTable { repo in
                let cs = Changeset<TestUser>.cast(nil, params: ["name": "Dan"], permitted: ["name"])

                do {
                    let _ = try await repo.update(cs)
                    Issue.record("Expected SpectroError to be thrown")
                } catch is SpectroError {
                    // Expected — update requires data != nil
                }
            }
        }

        @Test("Changeset insert inside transaction commits on success")
        func changesetInsideTransactionCommits() async throws {
            try await withCleanTable { repo in
                try await repo.transaction { tx in
                    let cs = Changeset<TestUser>.cast(nil, params: ["name": "Eve", "email": "eve@test.com", "age": 28], permitted: ["name", "email", "age"])
                        .validateRequired(["name", "email"])
                    let _ = try await tx.insert(cs)
                    return ()
                }

                let all = try await repo.all(TestUser.self)
                #expect(all.count == 1)
                #expect(all.first?.name == "Eve")
            }
        }

        @Test("Changeset insert inside transaction rolls back on error")
        func changesetInsideTransactionRollsBack() async throws {
            try await withCleanTable { repo in
                do {
                    try await repo.transaction { tx in
                        let cs = Changeset<TestUser>.cast(nil, params: ["name": "Frank", "email": "frank@test.com", "age": 35], permitted: ["name", "email", "age"])
                            .validateRequired(["name", "email"])
                        let _ = try await tx.insert(cs)
                        throw SpectroError.databaseError(reason: "Simulated failure")
                    }
                } catch is SpectroError {
                    // Expected rollback
                }

                let all = try await repo.all(TestUser.self)
                #expect(all.isEmpty)
            }
        }
    }
}
