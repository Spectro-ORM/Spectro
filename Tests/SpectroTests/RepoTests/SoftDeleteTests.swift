import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Soft Delete")
struct SoftDeleteTests {

    private func withCleanTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "soft_users" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL DEFAULT '',
                "email" TEXT NOT NULL DEFAULT '',
                "deleted_at" TIMESTAMPTZ
            )
        """)
        try await repo.executeRawSQL(#"TRUNCATE "soft_users""#)
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    @Test("delete() sets deleted_at instead of hard-deleting the row")
    func softDeleteSetsDeletedAt() async throws {
        try await withCleanTable { repo in
            let user = try await repo.insert(SoftUser(name: "Alice", email: "alice@test.com"))
            try await repo.delete(SoftUser.self, id: user.id)

            // Row still exists in the database
            let rows = try await repo.executeRawQuery(
                sql: #"SELECT deleted_at FROM "soft_users" WHERE id = $1"#,
                parameters: [user.id.toPostgresData()]
            )
            #expect(rows.count == 1)
            let ra = rows[0].makeRandomAccess()
            #expect(ra[data: "deleted_at"].date != nil)
        }
    }

    @Test("all() excludes soft-deleted records")
    func allExcludesSoftDeleted() async throws {
        try await withCleanTable { repo in
            let _ = try await repo.insert(SoftUser(name: "Bob", email: "bob@test.com"))
            let toDelete = try await repo.insert(SoftUser(name: "Carol", email: "carol@test.com"))
            try await repo.delete(SoftUser.self, id: toDelete.id)

            let all = try await repo.all(SoftUser.self)
            #expect(all.count == 1)
            #expect(all.first?.name == "Bob")
        }
    }

    @Test("get() returns nil for soft-deleted record")
    func getExcludesSoftDeleted() async throws {
        try await withCleanTable { repo in
            let user = try await repo.insert(SoftUser(name: "Dan", email: "dan@test.com"))
            try await repo.delete(SoftUser.self, id: user.id)

            let fetched = try await repo.get(SoftUser.self, id: user.id)
            #expect(fetched == nil)
        }
    }

    @Test("Query excludes soft-deleted records automatically")
    func queryExcludesSoftDeleted() async throws {
        try await withCleanTable { repo in
            let _ = try await repo.insert(SoftUser(name: "Eve", email: "eve@test.com"))
            let toDelete = try await repo.insert(SoftUser(name: "Frank", email: "frank@test.com"))
            try await repo.delete(SoftUser.self, id: toDelete.id)

            let results = try await repo.query(SoftUser.self).all()
            #expect(results.count == 1)
            #expect(results.first?.name == "Eve")
        }
    }

    @Test("withDeleted() returns all records including soft-deleted")
    func withDeletedIncludesAll() async throws {
        try await withCleanTable { repo in
            let _ = try await repo.insert(SoftUser(name: "Grace", email: "grace@test.com"))
            let toDelete = try await repo.insert(SoftUser(name: "Hank", email: "hank@test.com"))
            try await repo.delete(SoftUser.self, id: toDelete.id)

            let all = try await repo.query(SoftUser.self).withDeleted().all()
            #expect(all.count == 2)
        }
    }

    @Test("Hard-delete schema is unaffected by soft-delete logic")
    func hardDeleteSchemaUnaffected() async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()
        defer { Task { await spectro.shutdown() } }

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

        let user = try await repo.insert(TestUser(name: "Iris", email: "iris@test.com", age: 30))
        try await repo.delete(TestUser.self, id: user.id)

        // Hard-deleted: row is gone
        let all = try await repo.all(TestUser.self)
        #expect(all.isEmpty)
    }

    @Test("delete() is idempotent: second soft-delete is a no-op")
    func softDeleteIdempotent() async throws {
        try await withCleanTable { repo in
            let user = try await repo.insert(SoftUser(name: "Jay", email: "jay@test.com"))
            try await repo.delete(SoftUser.self, id: user.id)
            // Second delete should not throw
            try await repo.delete(SoftUser.self, id: user.id)

            let fetched = try await repo.get(SoftUser.self, id: user.id)
            #expect(fetched == nil)
        }
    }
}
}
