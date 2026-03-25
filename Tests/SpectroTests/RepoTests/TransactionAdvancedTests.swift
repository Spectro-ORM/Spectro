import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
    @Suite("Transaction Advanced")
    struct TransactionAdvancedTests {

        // MARK: - Helpers

        private func withRelationshipTables(
            _ body: (GenericDatabaseRepo) async throws -> Void
        ) async throws {
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
            try await repo.executeRawSQL("""
                CREATE TABLE IF NOT EXISTS "test_posts" (
                    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    "title" TEXT NOT NULL DEFAULT '',
                    "body" TEXT NOT NULL DEFAULT '',
                    "user_id" UUID NOT NULL,
                    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
            """)
            try await repo.executeRawSQL(#"TRUNCATE "test_posts""#)
            try await repo.executeRawSQL(#"TRUNCATE "test_users" CASCADE"#)
            do {
                try await body(repo)
            } catch {
                await spectro.shutdown()
                throw error
            }
            await spectro.shutdown()
        }

        private func withCleanTable(
            _ body: (GenericDatabaseRepo) async throws -> Void
        ) async throws {
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

        // MARK: - Raw SQL via Repo protocol in transactions

        @Test("executeRawSQL works through Repo protocol in transaction")
        func rawSQLInTransaction() async throws {
            try await withCleanTable { repo in
                try await repo.transaction { tx in
                    try await tx.executeRawSQL("""
                        INSERT INTO "test_users" ("name", "email", "age")
                        VALUES ('RawAlice', 'raw@test.com', 30)
                    """)
                    return ()
                }
                let all = try await repo.all(TestUser.self)
                #expect(all.count == 1)
                #expect(all.first?.name == "RawAlice")
            }
        }

        @Test("executeRawQuery works through Repo protocol in transaction")
        func rawQueryInTransaction() async throws {
            try await withCleanTable { repo in
                let _ = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                let _ = try await repo.insert(TestUser(name: "Bob", email: "b@test.com", age: 25))

                let count: Int = try await repo.transaction { tx in
                    let rows = try await tx.executeRawQuery(
                        sql: "SELECT COUNT(*) as cnt FROM \"test_users\" WHERE \"age\" > $1",
                        parameters: [.init(int: 26)]
                    )
                    let ra = rows.first!.makeRandomAccess()
                    return ra[data: "cnt"].int ?? 0
                }
                #expect(count == 1)
            }
        }

        // MARK: - Column validation in update()

        @Test("update with unknown column throws invalidSchema")
        func updateUnknownColumnThrows() async throws {
            try await withCleanTable { repo in
                let user = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                do {
                    let _ = try await repo.update(
                        TestUser.self,
                        id: user.id,
                        changes: ["nonExistentColumn": "value"]
                    )
                    Issue.record("Expected invalidSchema error for unknown column")
                } catch let error as SpectroError {
                    guard case .invalidSchema(let reason) = error else {
                        Issue.record("Wrong error: \(error)")
                        return
                    }
                    #expect(reason.contains("Unknown column"))
                }
            }
        }

        @Test("update with valid column succeeds")
        func updateValidColumnSucceeds() async throws {
            try await withCleanTable { repo in
                let user = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                let updated = try await repo.update(
                    TestUser.self,
                    id: user.id,
                    changes: ["name": "Bob"]
                )
                #expect(updated.name == "Bob")
            }
        }

        @Test("update with unknown column throws inside transaction")
        func updateUnknownColumnInTransactionThrows() async throws {
            try await withCleanTable { repo in
                let user = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                do {
                    try await repo.transaction { tx in
                        let _ = try await tx.update(
                            TestUser.self,
                            id: user.id,
                            changes: ["hackerColumn": "DROP TABLE"]
                        )
                    }
                    Issue.record("Expected invalidSchema error")
                } catch let error as SpectroError {
                    guard case .invalidSchema = error else {
                        Issue.record("Wrong error: \(error)")
                        return
                    }
                }
            }
        }

        // MARK: - Preloading inside transactions

        @Test("Query with where works inside transaction using relationship tables")
        func queryWithWhereInTransaction() async throws {
            try await withRelationshipTables { repo in
                let _ = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                let _ = try await repo.insert(TestUser(name: "Bob", email: "b@test.com", age: 25))

                let users: [TestUser] = try await repo.transaction { tx in
                    try await tx.query(TestUser.self)
                        .where { $0.age > 26 }
                        .all()
                }
                #expect(users.count == 1)
                #expect(users.first?.name == "Alice")
            }
        }

        @Test("Query builder with where + orderBy + limit inside transaction")
        func queryBuilderFullChainInTransaction() async throws {
            try await withCleanTable { repo in
                let _ = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                let _ = try await repo.insert(TestUser(name: "Bob", email: "b@test.com", age: 25))
                let _ = try await repo.insert(TestUser(name: "Charlie", email: "c@test.com", age: 35))

                let result: [TestUser] = try await repo.transaction { tx in
                    try await tx.query(TestUser.self)
                        .where { $0.age >= 28 }
                        .orderBy(\.name, .desc)
                        .limit(2)
                        .all()
                }
                #expect(result.count == 2)
                #expect(result[0].name == "Charlie")
                #expect(result[1].name == "Alice")
            }
        }

        @Test("Aggregates work inside transaction")
        func aggregatesInTransaction() async throws {
            try await withCleanTable { repo in
                let _ = try await repo.insert(TestUser(name: "Alice", email: "a@test.com", age: 30))
                let _ = try await repo.insert(TestUser(name: "Bob", email: "b@test.com", age: 20))

                let sum: Double? = try await repo.transaction { tx in
                    try await tx.query(TestUser.self).sum { $0.age }
                }
                #expect(sum == 50.0)
            }
        }
    }
}
