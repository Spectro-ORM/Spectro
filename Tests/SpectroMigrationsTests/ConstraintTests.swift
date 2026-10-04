import Foundation
import Testing
import SpectroCommon
import SpectroMigrations

struct CreateIssues: Migration {
    static let id = "1791129602_create_issues"
    var change: MigrationPlan {
        CreateTable("issues") { table in
            table.column("id", .uuid).primaryKey().default(.sql("gen_random_uuid()"))
            table.column("author_id", .uuid).notNull().references("users", column: "id", onDelete: .restrict)
            table.column("title", .text).notNull()
            table.column("priority", .integer).notNull().default(0)
            table.check("issues_priority_nonnegative", sql: "priority >= 0")
            table.timestamps()
        }
        CreateIndex("issues_author_id_index", on: "issues", columns: ["author_id"])
    }
}

@Suite("Migration constraints")
struct ConstraintTests {
    @Test("References and named checks are explicit; no FK index is inferred")
    func constraints() throws {
        let sql = try MigrationCompiler.prepare(CreateIssues()).upSQL
        #expect(sql.contains(#"CONSTRAINT "issues_author_id_fkey" REFERENCES "users" ("id") ON DELETE RESTRICT"#))
        #expect(sql.contains("CONSTRAINT \"issues_priority_nonnegative\" CHECK (priority >= 0\n)"))
        #expect(sql.components(separatedBy: "CREATE INDEX").count == 2)
    }

    struct Partial: Migration {
        static let id = "1700000013_partial"
        var change: MigrationPlan {
            AlterTable("issues", schema: "audit") { table in
                table.add("user_id", .uuid).references("users", schema: "accounts", name: "user_fk")
            }
            CreateIndex("active_title_index", on: "issues", columns: ["title"], schema: "audit")
                .unique().whereSQL("active = TRUE")
        }
    }

    @Test("Qualified references and partial unique indexes render independently")
    func partial() throws {
        let sql = try MigrationCompiler.prepare(Partial()).upSQL
        #expect(sql.contains(#"CONSTRAINT "user_fk" REFERENCES "accounts"."users" ("id")"#))
        #expect(sql.contains("ON \"audit\".\"issues\" (\"title\") WHERE (active = TRUE\n)"))
    }

    struct Invalid: Migration {
        static let id = "1700000014_invalid"
        let kind: Int
        var change: MigrationPlan {
            if kind == 0 {
                CreateTable("bad") { $0.column("x", .integer).notNull().references("users", onDelete: .setNull) }
            } else if kind == 1 {
                CreateTable("bad") { $0.column("x", .integer).references("users", onDelete: .setDefault) }
            } else if kind == 2 {
                CreateTable("bad") {
                    $0.column("x", .integer)
                    $0.check("bad_check", sql: " ")
                }
            } else if kind == 3 {
                CreateTable("bad") {
                    $0.column("x", .integer)
                    $0.check("same", sql: "x > 0")
                    $0.check("same", sql: "x < 10")
                }
            } else if kind == 4 {
                CreateIndex("idx", on: "bad", columns: ["x"]).whereSQL("")
            } else {
                CreateIndex("idx", on: "bad", columns: ["x"]).whereSQL("true").whereSQL("false")
            }
        }
    }

    @Test("Contradictory references and invalid constraints fail planning", arguments: 0...5)
    func invalid(kind: Int) {
        #expect(throws: MigrationPlanningError.self) { try MigrationCompiler.prepare(Invalid(kind: kind)) }
    }
}
