import Testing
import PostgresKit
@testable import Spectro

@Suite("Query binding order")
struct QueryBindingTests {
    private actor Recorder: QueryExecutor {
        var bindings: [[String]] = []
        var statements: [String] = []

        func executeQuery<T: Sendable>(
            sql: String, parameters: [PostgresData],
            resultMapper: @Sendable @escaping (PostgresRow) throws -> T
        ) async throws -> [T] {
            bindings.append(parameters.map { $0.string ?? "?" })
            statements.append(sql)
            return []
        }
    }

    private struct SoftPost: Schema {
        static let tableName = "soft_posts"
        static var softDeleteColumn: String? { "deleted_at" }
        init() {}
    }

    @Test("Typed joins qualify the implicit soft-delete filter")
    func softDeleteJoin() async throws {
        let recorder = Recorder()
        let query = Query(schema: SoftUser.self, executor: recorder)
            .join(SoftPost.self, on: { _ in QueryCondition(sql: "TRUE") })
        _ = try await query.executeJoin(with: SoftPost.self).all()
        #expect(await recorder.statements.first?.contains("WHERE \"\(SoftUser.tableName)\".\"deleted_at\" IS NULL") == true)
    }

    @Test("Join parameters precede filters regardless of builder call order")
    func bindingsFollowSQL() async throws {
        let recorder = Recorder()
        let base = Query(schema: TestUser.self, executor: recorder).where { $0.name == "Alice" }
        let query = base.join(TestPost.self, on: { $0.right.title == "Article" })
        #expect(query.buildSQL().contains("\"test_posts\".\"title\" = $1"))
        #expect(query.buildSQL().contains("\"name\" = $2"))
        _ = try await query.all()
        _ = try await query.count()
        _ = try await query.sum { $0.age }
        _ = try await query.select { $0.name }.all()
        _ = try await query.groupBy { $0.name }.having { $0.name != "Excluded" }.groupedCount()
        _ = try await query.executeJoin(with: TestPost.self).where { $0.joined.title == "Second" }.all()
        #expect(await recorder.bindings == [
            ["Article", "Alice"], ["Article", "Alice"], ["Article", "Alice"],
            ["Article", "Alice"], ["Article", "Alice", "Excluded"], ["Article", "Alice", "Second"]
        ])
        #expect(await recorder.statements.allSatisfy { !$0.contains("?") })
        #expect(base.parameters.map(\.string) == ["Alice"])
    }
}
