import SpectroMigrations

struct AddIssueArchive: Migration {
    static let id = "1700000002_add_issue_archive"

    var change: MigrationPlan {
        AlterTable("issues") { table in
            table.add("archived", .boolean).notNull().default(false)
        }
        CreateIndex("issues_unarchived_index", on: "issues", columns: ["project_id"])
            .whereSQL("NOT archived")
    }
}
