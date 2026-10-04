import Testing
import SpectroCommon
import SpectroMigrations

@Suite("Explicit migration rollback")
struct ControlFlowTests {
    struct Explicit: Migration {
        static let id = "1700000010_explicit"
        var change: MigrationPlan {
            SQL(up: "SELECT 'a;b'", down: "SELECT 'undo'")
            Reversible {
                DropTable("old")
                CreateTable("new") { $0.column("id", .integer) }
            } down: {
                DropTable("new")
                CreateTable("old") { $0.column("id", .integer) }
                Reversible { SQL("SELECT 'wrong'") } down: { SQL("SELECT 'nested down'") }
            }
        }
    }

    @Test("Explicit down operations retain declaration order and nested branch direction")
    func explicitOrder() throws {
        let prepared = try MigrationCompiler.prepare(Explicit())
        guard case .sql(let down) = prepared.rollback else { Issue.record("Expected rollback"); return }
        #expect(down.hasPrefix("DROP TABLE \"new\";"))
        #expect(down.contains("CREATE TABLE \"old\""))
        #expect(down.contains("SELECT 'nested down'"))
        #expect(!down.contains("wrong"))
        #expect(down.hasSuffix("SELECT 'undo'\n;"))
    }

    struct Destructive: Migration {
        static let id = "1700000011_destructive"
        var change: MigrationPlan {
            Irreversible("Expired events cannot be reconstructed") { SQL("DELETE FROM events") }
        }
    }

    @Test("Irreversibility is retained as an explicit reason")
    func irreversible() throws {
        let prepared = try MigrationCompiler.prepare(Destructive())
        #expect(prepared.rollback == .irreversible(reason: "Expired events cannot be reconstructed"))
    }

    struct Invalid: Migration {
        static let id = "1700000012_invalid"
        let kind: Int
        var change: MigrationPlan {
            SQL(up: "SELECT 1", down: "SELECT 2")
            if kind == 0 { SQL("DELETE FROM events") }
            if kind == 1 { DropTable("events") }
            if kind == 2 { Reversible { SQL("SELECT 1") } down: {} }
            if kind == 3 { SQL(up: "SELECT 1", down: "-- empty") }
            if kind == 4 { Irreversible(" ") { SQL("DELETE FROM events") } }
            if kind == 5 {
                Reversible { SQL("SELECT 1") } down: {
                    Irreversible("Wrong branch") { SQL("SELECT 2") }
                }
            }
            if kind == 6 { SQL(up: "COMMIT", down: "SELECT 2") }
        }
    }

    @Test("Unsafe or empty explicit operations are diagnosed", arguments: 0...6)
    func invalid(kind: Int) {
        #expect(throws: MigrationPlanningError.self) { try MigrationCompiler.prepare(Invalid(kind: kind)) }
    }
}
