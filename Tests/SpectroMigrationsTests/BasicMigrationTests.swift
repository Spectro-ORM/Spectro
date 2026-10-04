import Foundation
import Testing
import Spectro
import SpectroCommon
import SpectroMigrations

struct CreateUsers: Migration {
    static let id = "1791129600_create_users"
    var change: MigrationPlan {
        CreateTable("users") { table in
            table.column("id", .uuid).primaryKey().default(.sql("gen_random_uuid()"))
            table.column("email", .text).notNull()
            table.column("display_name", .text)
            table.column("active", .boolean).notNull().default(true)
            table.timestamps()
        }
        CreateIndex("users_email_index", on: "users", columns: ["email"]).unique()
    }
}

@Suite("Migration DSL")
struct BasicMigrationTests {
    struct ExistingModel {
        @Column var name: String = ""
    }

    @Test("Creates declared columns and reverses the index before the table")
    func createTable() throws {
        let migration = try MigrationCompiler.prepare(CreateUsers())
        #expect(migration.version == "1791129600_create_users")
        #expect(migration.upSQL.contains(#""email" TEXT NOT NULL"#))
        #expect(migration.upSQL.contains(#""active" BOOLEAN NOT NULL DEFAULT TRUE"#))
        #expect(migration.upSQL.contains(#""created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP"#))
        #expect(migration.upSQL.contains(#"CREATE UNIQUE INDEX "users_email_index" ON "users" ("email")"#))
        guard case .sql(let down) = migration.rollback else { Issue.record("Missing inverse"); return }
        let index = try #require(down.range(of: "DROP INDEX"))
        let table = try #require(down.range(of: "DROP TABLE"))
        #expect(index.lowerBound < table.lowerBound)
        #expect(ExistingModel().name == "")
    }

    struct ExtendProfile: Migration {
        static let id = "1700000002_extend_profile"
        var change: MigrationPlan {
            AlterTable("users") { table in
                table.rename("display_name", to: "nickname")
                table.add("bio", .text)
            }
        }
    }

    @Test("Nested alterations reverse their operation order")
    func alterationOrder() throws {
        let migration = try MigrationCompiler.prepare(ExtendProfile())
        guard case .sql(let down) = migration.rollback else { Issue.record("Missing inverse"); return }
        #expect(down.contains(#"RENAME COLUMN "nickname" TO "display_name""#))
        let drop = try #require(down.range(of: "DROP COLUMN"))
        let rename = try #require(down.range(of: "RENAME COLUMN"))
        #expect(drop.lowerBound < rename.lowerBound)
    }

    struct Quoted: Migration {
        static let id = "1700000003_quoted"
        var change: MigrationPlan {
            CreateTable("we\"ird.table", schema: "order") { table in
                table.column("value", .text).default("O'Reilly\\path")
                table.column("empty", .text).default("")
            }
        }
    }

    @Test("Identifiers, schemas and string literals have separate escaping")
    func quoting() throws {
        let sql = try MigrationCompiler.prepare(Quoted()).upSQL
        #expect(sql.contains(#""order"."we""ird.table""#))
        #expect(sql.contains(#"E'O''Reilly\\path'"#))
        #expect(sql.contains("DEFAULT E''"))
    }

    struct Invalid: Migration {
        static let id = "1700000004_invalid"
        let kind: String
        var change: MigrationPlan {
            CreateTable("invalid") { table in
                if kind == "duplicate" {
                    table.column("x", .text)
                    table.column("x", .text)
                } else if kind == "modifier" {
                    table.column("x", .text).notNull().notNull()
                } else if kind == "varchar" {
                    table.column("x", .varchar(length: 0))
                } else if kind == "numeric" {
                    table.column("x", .numeric(precision: 2, scale: 3))
                } else if kind == "primary" {
                    table.column("x", .integer).primaryKey()
                    table.column("y", .integer).primaryKey()
                } else if kind == "nonfinite" {
                    table.column("x", .numeric(precision: 9, scale: 2)).default(.floating(.infinity))
                } else if kind == "default" {
                    table.column("x", .text).default("a").default("b")
                } else {
                    table.column(kind, .text)
                }
            }
        }
    }

    @Test("Invalid structure fails before SQL execution", arguments: [
        "duplicate", "modifier", "varchar", "numeric", "primary", "nonfinite", "default", "", "\0", String(repeating: "é", count: 32)
    ])
    func invalidDefinitions(kind: String) throws {
        do {
            _ = try MigrationCompiler.prepare(Invalid(kind: kind))
            Issue.record("Expected rejection of \(kind)")
        } catch let error as MigrationPlanningError {
            #expect(error.migrationID == Invalid.id)
            #expect(error.operationIndex == 0)
        }
    }

    struct EmptyIndex: Migration {
        static let id = "1700000005_empty_index"
        var change: MigrationPlan { CreateIndex("empty", on: "users", columns: []) }
    }

    @Test("An empty index is rejected")
    func emptyIndex() {
        #expect(throws: MigrationPlanningError.self) { try MigrationCompiler.prepare(EmptyIndex()) }
    }

    struct EmptyMigration: Migration {
        static let id = "1700000006_empty"
        var change: MigrationPlan { get {} }
    }

    @Test("Generated empty declarations cannot be applied")
    func emptyMigration() {
        #expect(throws: MigrationPlanningError.self) { try MigrationCompiler.prepare(EmptyMigration()) }
    }
}
