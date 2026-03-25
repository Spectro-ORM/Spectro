import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
    @Suite("Transactions")
    struct TransactionTests {

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

        @Test("Committed transaction persists data")
        func committedTransactionPersists() async throws {
            try await withCleanTable { repo in
                try await repo.transaction { tx in
                    let _ = try await tx.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                    return ()
                }
                let all = try await repo.all(TestUser.self)
                #expect(all.count == 1)
                #expect(all.first?.name == "Alice")
            }
        }

        @Test("Failed transaction rolls back all changes")
        func failedTransactionRollsBack() async throws {
            try await withCleanTable { repo in
                do {
                    try await repo.transaction { tx in
                        let _ = try await tx.insert(TestUser(name: "Bob", email: "b@test.com", age: 25))
                        throw SpectroError.invalidSchema(reason: "deliberate failure")
                    }
                    Issue.record("Transaction should have thrown")
                } catch {
                    // Expected — transaction failed
                }
                let all = try await repo.all(TestUser.self)
                #expect(all.isEmpty, "Rolled-back insert should not persist")
            }
        }

        @Test("Transaction supports multiple operations atomically")
        func multipleOperationsAtomic() async throws {
            try await withCleanTable { repo in
                try await repo.transaction { tx in
                    let _ = try await tx.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                    let _ = try await tx.insert(TestUser(name: "Bob", email: "b@test.com", age: 25))
                    let _ = try await tx.insert(TestUser(name: "Charlie", email: "c@test.com", age: 35))
                    return ()
                }
                let all = try await repo.all(TestUser.self)
                #expect(all.count == 3)
            }
        }

        @Test("Partial failure rolls back all operations in transaction")
        func partialFailureRollsBackAll() async throws {
            try await withCleanTable { repo in
                do {
                    try await repo.transaction { tx in
                        let _ = try await tx.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                        let _ = try await tx.insert(TestUser(name: "Bob", email: "b@test.com", age: 25))
                        // Third insert fails
                        throw SpectroError.invalidSchema(reason: "deliberate failure after two inserts")
                    }
                    Issue.record("Transaction should have thrown")
                } catch {
                    // Expected
                }
                let all = try await repo.all(TestUser.self)
                #expect(all.isEmpty, "All inserts should be rolled back")
            }
        }

        @Test("Query builder works inside transaction")
        func queryBuilderInTransaction() async throws {
            try await withCleanTable { repo in
                // Seed data outside transaction
                let _ = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                let _ = try await repo.insert(TestUser(name: "Bob", email: "b@test.com", age: 25))
                let _ = try await repo.insert(TestUser(name: "Charlie", email: "c@test.com", age: 35))

                let result: [TestUser] = try await repo.transaction { tx in
                    try await tx.query(TestUser.self)
                        .where { $0.age > 26 }
                        .orderBy(\.name)
                        .all()
                }
                #expect(result.count == 2)
                #expect(result[0].name == "Alice")
                #expect(result[1].name == "Charlie")
            }
        }

        @Test("Transaction can read its own writes")
        func readOwnWrites() async throws {
            try await withCleanTable { repo in
                let found: TestUser? = try await repo.transaction { tx in
                    let _ = try await tx.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                    return try await tx.query(TestUser.self)
                        .where { $0.name == "Alice" }
                        .first()
                }
                #expect(found != nil)
                #expect(found?.name == "Alice")
            }
        }

        @Test("Nested transaction throws transactionAlreadyStarted")
        func nestedTransactionThrows() async throws {
            try await withCleanTable { repo in
                do {
                    try await repo.transaction { tx in
                        try await tx.transaction { _ in
                            return ()
                        }
                    }
                    Issue.record("Nested transaction should have thrown")
                } catch let error as SpectroError {
                    guard case .transactionAlreadyStarted = error else {
                        Issue.record("Wrong error: \(error)")
                        return
                    }
                }
            }
        }

        @Test("Transaction return value is propagated")
        func returnValuePropagated() async throws {
            try await withCleanTable { repo in
                let user: TestUser = try await repo.transaction { tx in
                    try await tx.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                }
                #expect(user.name == "Alice")
            }
        }
    }
}
