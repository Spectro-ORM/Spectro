import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Non-UUID Primary Key CRUD", .serialized)
struct NonUUIDPrimaryKeyTests {

    // MARK: - Int PK Table Setup

    private func withIntPKTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()
        try await repo.executeRawSQL("DROP TABLE IF EXISTS \"int_pk_items\"")
        try await repo.executeRawSQL("""
            CREATE TABLE "int_pk_items" (
                "id" SERIAL PRIMARY KEY,
                "name" TEXT NOT NULL DEFAULT ''
            )
        """)
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    // MARK: - String PK Table Setup

    private func withStringPKTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "string_pk_items" (
                "id" TEXT PRIMARY KEY,
                "name" TEXT NOT NULL DEFAULT ''
            )
        """)
        try await repo.executeRawSQL("TRUNCATE \"string_pk_items\"")
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    // MARK: - Int PK CRUD Tests

    @Test("Insert with Int PK and query back")
    func intPKInsertAndQuery() async throws {
        try await withIntPKTable { repo in
            let item = IntPKItem(name: "Widget")
            let inserted = try await repo.insert(item)

            #expect(inserted.name == "Widget")
            // SERIAL auto-assigns a positive integer id
            #expect(inserted.id > 0)

            // Verify it exists in the database
            let all = try await repo.all(IntPKItem.self)
            #expect(all.count == 1)
            #expect(all.first?.name == "Widget")
            #expect(all.first?.id == inserted.id)
        }
    }

    @Test("Get by Int id")
    func intPKGetById() async throws {
        try await withIntPKTable { repo in
            let inserted = try await repo.insert(IntPKItem(name: "Gadget"))

            let fetched = try await repo.get(IntPKItem.self, id: inserted.id)
            #expect(fetched != nil)
            #expect(fetched?.id == inserted.id)
            #expect(fetched?.name == "Gadget")
        }
    }

    @Test("Get by Int id returns nil for non-existent id")
    func intPKGetReturnsNilForMissing() async throws {
        try await withIntPKTable { repo in
            let result = try await repo.get(IntPKItem.self, id: 99999)
            #expect(result == nil)
        }
    }

    @Test("Update by Int id")
    func intPKUpdate() async throws {
        try await withIntPKTable { repo in
            let inserted = try await repo.insert(IntPKItem(name: "Original"))

            let updated = try await repo.update(
                IntPKItem.self,
                id: inserted.id,
                changes: ["name": "Updated"]
            )

            #expect(updated.id == inserted.id)
            #expect(updated.name == "Updated")

            // Verify the change persisted
            let fetched = try await repo.get(IntPKItem.self, id: inserted.id)
            #expect(fetched?.name == "Updated")
        }
    }

    @Test("Delete by Int id")
    func intPKDelete() async throws {
        try await withIntPKTable { repo in
            let inserted = try await repo.insert(IntPKItem(name: "ToDelete"))

            try await repo.delete(IntPKItem.self, id: inserted.id)

            let fetched = try await repo.get(IntPKItem.self, id: inserted.id)
            #expect(fetched == nil)

            let all = try await repo.all(IntPKItem.self)
            #expect(all.isEmpty)
        }
    }

    @Test("Multiple inserts with Int PK get sequential ids")
    func intPKSequentialIds() async throws {
        try await withIntPKTable { repo in
            let first = try await repo.insert(IntPKItem(name: "First"))
            let second = try await repo.insert(IntPKItem(name: "Second"))
            let third = try await repo.insert(IntPKItem(name: "Third"))

            #expect(first.id > 0)
            #expect(second.id == first.id + 1)
            #expect(third.id == second.id + 1)

            let all = try await repo.all(IntPKItem.self)
            #expect(all.count == 3)
        }
    }

    // MARK: - String PK CRUD Tests

    @Test("Insert with user-supplied String PK preserves the id")
    func stringPKInsertWithIncludePrimaryKey() async throws {
        try await withStringPKTable { repo in
            let item = StringPKItem(id: "slug-123", name: "Page")
            let inserted = try await repo.insert(item, includePrimaryKey: true)

            #expect(inserted.id == "slug-123")
            #expect(inserted.name == "Page")

            let fetched = try await repo.get(StringPKItem.self, id: "slug-123")
            #expect(fetched != nil)
            #expect(fetched?.id == "slug-123")
            #expect(fetched?.name == "Page")
        }
    }

    @Test("Get by String id returns nil for non-existent id")
    func stringPKGetReturnsNilForMissing() async throws {
        try await withStringPKTable { repo in
            let result = try await repo.get(StringPKItem.self, id: "does-not-exist")
            #expect(result == nil)
        }
    }

    @Test("All returns String PK rows inserted with includePrimaryKey")
    func stringPKAll() async throws {
        try await withStringPKTable { repo in
            _ = try await repo.insert(StringPKItem(id: "alpha", name: "First"), includePrimaryKey: true)
            _ = try await repo.insert(StringPKItem(id: "beta", name: "Second"), includePrimaryKey: true)

            let all = try await repo.all(StringPKItem.self)
            #expect(all.count == 2)

            let sorted = all.sorted { $0.id < $1.id }
            #expect(sorted[0].id == "alpha")
            #expect(sorted[0].name == "First")
            #expect(sorted[1].id == "beta")
            #expect(sorted[1].name == "Second")
        }
    }

    @Test("Update by String id")
    func stringPKUpdate() async throws {
        try await withStringPKTable { repo in
            _ = try await repo.insert(StringPKItem(id: "doc-1", name: "Original"), includePrimaryKey: true)

            let updated = try await repo.update(
                StringPKItem.self,
                id: "doc-1",
                changes: ["name": "Revised"]
            )

            #expect(updated.id == "doc-1")
            #expect(updated.name == "Revised")

            let fetched = try await repo.get(StringPKItem.self, id: "doc-1")
            #expect(fetched?.name == "Revised")
        }
    }

    @Test("Delete by String id")
    func stringPKDelete() async throws {
        try await withStringPKTable { repo in
            _ = try await repo.insert(StringPKItem(id: "remove-me", name: "Gone"), includePrimaryKey: true)

            try await repo.delete(StringPKItem.self, id: "remove-me")

            let fetched = try await repo.get(StringPKItem.self, id: "remove-me")
            #expect(fetched == nil)

            let all = try await repo.all(StringPKItem.self)
            #expect(all.isEmpty)
        }
    }

    // MARK: - includePrimaryKey Tests

    @Test("Insert with specific Int PK using includePrimaryKey")
    func intPKInsertWithIncludePrimaryKey() async throws {
        try await withIntPKTable { repo in
            // Override the table to not use SERIAL so we can supply our own
            try await repo.executeRawSQL("DROP TABLE IF EXISTS \"int_pk_items\"")
            try await repo.executeRawSQL("""
                CREATE TABLE "int_pk_items" (
                    "id" INTEGER PRIMARY KEY,
                    "name" TEXT NOT NULL DEFAULT ''
                )
            """)

            let item = IntPKItem(id: 42, name: "Custom ID")
            let inserted = try await repo.insert(item, includePrimaryKey: true)

            #expect(inserted.id == 42)
            #expect(inserted.name == "Custom ID")

            let fetched = try await repo.get(IntPKItem.self, id: 42)
            #expect(fetched?.id == 42)
            #expect(fetched?.name == "Custom ID")
        }
    }

    @Test("insertAll with includePrimaryKey preserves all user-supplied PKs")
    func insertAllWithIncludePrimaryKey() async throws {
        try await withStringPKTable { repo in
            let items = [
                StringPKItem(id: "batch-1", name: "First"),
                StringPKItem(id: "batch-2", name: "Second"),
                StringPKItem(id: "batch-3", name: "Third"),
            ]
            let results = try await repo.insertAll(items, includePrimaryKey: true)

            #expect(results.count == 3)
            let sorted = results.sorted { $0.id < $1.id }
            #expect(sorted[0].id == "batch-1")
            #expect(sorted[1].id == "batch-2")
            #expect(sorted[2].id == "batch-3")

            let all = try await repo.all(StringPKItem.self)
            #expect(all.count == 3)
        }
    }

    @Test("Upsert with includePrimaryKey inserts then updates on conflict")
    func upsertWithIncludePrimaryKey() async throws {
        try await withStringPKTable { repo in
            let item = StringPKItem(id: "upsert-key", name: "Original")
            let inserted = try await repo.upsert(
                item,
                conflictTarget: .columns(["id"]),
                set: ["name"],
                includePrimaryKey: true
            )
            #expect(inserted.id == "upsert-key")
            #expect(inserted.name == "Original")

            let updated = StringPKItem(id: "upsert-key", name: "Updated")
            let upserted = try await repo.upsert(
                updated,
                conflictTarget: .columns(["id"]),
                set: ["name"],
                includePrimaryKey: true
            )
            #expect(upserted.id == "upsert-key")
            #expect(upserted.name == "Updated")

            let all = try await repo.all(StringPKItem.self)
            #expect(all.count == 1)
        }
    }

    @Test("Insert without includePrimaryKey still excludes PK (backward compat)")
    func insertWithoutFlagExcludesPK() async throws {
        try await withIntPKTable { repo in
            // Default behavior: SERIAL assigns the PK
            let inserted = try await repo.insert(IntPKItem(name: "AutoPK"))
            #expect(inserted.id > 0)
            #expect(inserted.name == "AutoPK")
        }
    }

    @Test("getOrFail throws for missing Int id")
    func intPKGetOrFailThrows() async throws {
        try await withIntPKTable { repo in
            do {
                let _ = try await repo.getOrFail(IntPKItem.self, id: 99999)
                Issue.record("Expected SpectroError.notFound to be thrown")
            } catch is SpectroError {
                // Expected
            }
        }
    }

    @Test("getOrFail throws for missing String id")
    func stringPKGetOrFailThrows() async throws {
        try await withStringPKTable { repo in
            do {
                let _ = try await repo.getOrFail(StringPKItem.self, id: "nonexistent")
                Issue.record("Expected SpectroError.notFound to be thrown")
            } catch is SpectroError {
                // Expected
            }
        }
    }
}
}
