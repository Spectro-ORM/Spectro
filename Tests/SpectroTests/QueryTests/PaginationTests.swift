import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Pagination")
struct PaginationTests {

    private func withSeededTable(_ count: Int = 5, _ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let repo = try await TestDatabase.sharedRepo()
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
        if count > 0 {
            for i in 1...count {
                let _ = try await repo.insert(TestUser(name: "User\(i)", email: "user\(i)@test.com", age: 20 + i))
            }
        }
        try await body(repo)
    }

    @Test("First page returns correct slice and metadata")
    func firstPage() async throws {
        try await withSeededTable(5) { repo in
            let page = try await repo.query(TestUser.self).page(size: 2, page: 1)

            #expect(page.items.count == 2)
            #expect(page.totalCount == 5)
            #expect(page.pageSize == 2)
            #expect(page.pageNumber == 1)
            #expect(page.totalPages == 3)
            #expect(page.hasNextPage == true)
            #expect(page.hasPreviousPage == false)
        }
    }

    @Test("Last page returns remainder and correct metadata")
    func lastPage() async throws {
        try await withSeededTable(5) { repo in
            let page = try await repo.query(TestUser.self).page(size: 2, page: 3)

            #expect(page.items.count == 1)
            #expect(page.totalCount == 5)
            #expect(page.totalPages == 3)
            #expect(page.hasNextPage == false)
            #expect(page.hasPreviousPage == true)
        }
    }

    @Test("Empty result set returns zero items and one total page")
    func emptyResult() async throws {
        try await withSeededTable(0) { repo in
            let page = try await repo.query(TestUser.self).page(size: 10, page: 1)

            #expect(page.items.isEmpty)
            #expect(page.totalCount == 0)
            #expect(page.totalPages == 1)
            #expect(page.hasNextPage == false)
            #expect(page.hasPreviousPage == false)
        }
    }

    @Test("WHERE filter is respected in both count and items queries")
    func pageWithWhereFilter() async throws {
        try await withSeededTable(5) { repo in
            // isActive defaults to true for all 5 — insert one inactive
            let _ = try await repo.insert(TestUser(name: "Inactive", email: "inactive@test.com", age: 99, isActive: false))

            let page = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .page(size: 10, page: 1)

            #expect(page.totalCount == 5)
            #expect(page.items.count == 5)
            #expect(page.items.allSatisfy { $0.isActive })
        }
    }

    @Test("Page size exceeding total returns all records")
    func pageSizeExceedingTotal() async throws {
        try await withSeededTable(3) { repo in
            let page = try await repo.query(TestUser.self).page(size: 100, page: 1)

            #expect(page.items.count == 3)
            #expect(page.totalCount == 3)
            #expect(page.totalPages == 1)
            #expect(page.hasNextPage == false)
        }
    }

    @Test("Default page argument is 1")
    func defaultPageArgument() async throws {
        try await withSeededTable(3) { repo in
            let page = try await repo.query(TestUser.self).page(size: 2)
            #expect(page.pageNumber == 1)
            #expect(page.items.count == 2)
        }
    }
}
}
