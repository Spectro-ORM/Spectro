import SpectroMigrations

struct CreateFixtureUsers: Migration {
    static let id = "1700000001_create_fixture_users"
    var change: MigrationPlan {
        CreateTable("fixture_users") { table in
            table.column("id", .uuid).primaryKey().default(.sql("gen_random_uuid()"))
            table.column("email", .text).notNull()
            table.column("active", .boolean).notNull().default(true)
            table.timestamps()
        }
        CreateIndex("fixture_users_email_index", on: "fixture_users", columns: ["email"]).unique()
    }
}

struct AddLegacyPriority: Migration {
    static let id = "1700000002_add_legacy_priority"
    var change: MigrationPlan {
        AlterTable("legacy_items") { table in table.add("priority", .integer).notNull().default(0) }
        CreateIndex("legacy_priority_index", on: "legacy_items", columns: ["priority"])
    }
}

