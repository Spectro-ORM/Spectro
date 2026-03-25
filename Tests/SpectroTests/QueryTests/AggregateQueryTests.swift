import Foundation
import Testing
import SpectroCommon
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Aggregate Queries")
struct AggregateQueryTests {

    private func withSeededTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
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
        try await repo.executeRawSQL("TRUNCATE \"test_users\"")
        let _ = try await repo.insert(TestUser(name: "Alice", email: "alice@test.com", age: 30, isActive: true))
        let _ = try await repo.insert(TestUser(name: "Bob", email: "bob@test.com", age: 25, isActive: true))
        let _ = try await repo.insert(TestUser(name: "Charlie", email: "charlie@test.com", age: 35, isActive: false))
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    private func withEmptyTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
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
        try await repo.executeRawSQL("TRUNCATE \"test_users\"")
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    // MARK: - Sum

    @Test("sum returns total of numeric field")
    func testSumReturnsTotal() async throws {
        try await withSeededTable { repo in
            let total = try await repo.query(TestUser.self).sum { $0.age }
            #expect(total != nil)
            #expect(total == 90.0) // 30 + 25 + 35
        }
    }

    // MARK: - Avg

    @Test("avg returns average of numeric field")
    func testAvgReturnsAverage() async throws {
        try await withSeededTable { repo in
            let average = try await repo.query(TestUser.self).avg { $0.age }
            #expect(average != nil)
            #expect(average == 30.0) // (30 + 25 + 35) / 3
        }
    }

    // MARK: - Min

    @Test("min returns minimum value of numeric field")
    func testMinReturnsMinimum() async throws {
        try await withSeededTable { repo in
            let minimum = try await repo.query(TestUser.self).min { $0.age }
            #expect(minimum != nil)
            #expect(minimum == 25.0) // Bob's age
        }
    }

    // MARK: - Max

    @Test("max returns maximum value of numeric field")
    func testMaxReturnsMaximum() async throws {
        try await withSeededTable { repo in
            let maximum = try await repo.query(TestUser.self).max { $0.age }
            #expect(maximum != nil)
            #expect(maximum == 35.0) // Charlie's age
        }
    }

    // MARK: - Empty table

    @Test("aggregates return nil on empty table")
    func testAggregateOnEmptyTableReturnsNil() async throws {
        try await withEmptyTable { repo in
            let sumResult = try await repo.query(TestUser.self).sum { $0.age }
            let avgResult = try await repo.query(TestUser.self).avg { $0.age }
            let minResult = try await repo.query(TestUser.self).min { $0.age }
            let maxResult = try await repo.query(TestUser.self).max { $0.age }
            #expect(sumResult == nil)
            #expect(avgResult == nil)
            #expect(minResult == nil)
            #expect(maxResult == nil)
        }
    }

    // MARK: - With WHERE clause

    @Test("aggregate with where clause only considers filtered rows")
    func testAggregateWithWhereClause() async throws {
        try await withSeededTable { repo in
            // Only active users: Alice (30) and Bob (25)
            let total = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .sum { $0.age }
            #expect(total == 55.0) // 30 + 25

            let average = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .avg { $0.age }
            #expect(average == 27.5) // (30 + 25) / 2

            let minimum = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .min { $0.age }
            #expect(minimum == 25.0) // Bob

            let maximum = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .max { $0.age }
            #expect(maximum == 30.0) // Alice
        }
    }

    // MARK: - Grouped Aggregates

    @Test("groupedSum returns sum per group")
    func testGroupedSum() async throws {
        try await withSeededTable { repo in
            let results = try await repo.query(TestUser.self)
                .groupBy { $0.isActive }
                .groupedSum { $0.age }

            #expect(results.count == 2)

            let active = results.first { $0.group["is_active"] == "true" }
            let inactive = results.first { $0.group["is_active"] == "false" }

            #expect(active?.value == 55.0)   // Alice(30) + Bob(25)
            #expect(inactive?.value == 35.0)  // Charlie(35)
        }
    }

    @Test("groupedCount returns count per group")
    func testGroupedCount() async throws {
        try await withSeededTable { repo in
            let results = try await repo.query(TestUser.self)
                .groupBy { $0.isActive }
                .groupedCount()

            #expect(results.count == 2)

            let active = results.first { $0.group["is_active"] == "true" }
            let inactive = results.first { $0.group["is_active"] == "false" }

            #expect(active?.value == 2.0)
            #expect(inactive?.value == 1.0)
        }
    }

    @Test("groupedAvg with where filter")
    func testGroupedAvgWithFilter() async throws {
        try await withSeededTable { repo in
            // Only active users, grouped by is_active — should be one group
            let results = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .groupBy { $0.isActive }
                .groupedAvg { $0.age }

            #expect(results.count == 1)
            #expect(results.first?.value == 27.5) // (30 + 25) / 2
        }
    }

    @Test("groupedMin and groupedMax per group")
    func testGroupedMinMax() async throws {
        try await withSeededTable { repo in
            let minResults = try await repo.query(TestUser.self)
                .groupBy { $0.isActive }
                .groupedMin { $0.age }

            let maxResults = try await repo.query(TestUser.self)
                .groupBy { $0.isActive }
                .groupedMax { $0.age }

            let activeMin = minResults.first { $0.group["is_active"] == "true" }
            let activeMax = maxResults.first { $0.group["is_active"] == "true" }

            #expect(activeMin?.value == 25.0) // Bob
            #expect(activeMax?.value == 30.0) // Alice
        }
    }

    @Test("groupedSum without groupBy throws error")
    func testGroupedSumWithoutGroupByThrows() async throws {
        try await withSeededTable { repo in
            do {
                let _ = try await repo.query(TestUser.self)
                    .groupedSum { $0.age }
                Issue.record("Expected SpectroError.invalidQuery to be thrown")
            } catch is SpectroError {
                // Expected
            }
        }
    }

    @Test("multi-field groupBy works")
    func testMultiFieldGroupBy() async throws {
        try await withSeededTable { repo in
            let results = try await repo.query(TestUser.self)
                .groupBy({ $0.isActive }, { $0.name })
                .groupedCount()

            // Each user has a unique name, so each row is its own group
            #expect(results.count == 3)
            for result in results {
                #expect(result.value == 1.0)
            }
        }
    }
}
}
