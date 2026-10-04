import Testing
import SpectroCommon
import SpectroMigrations

private enum ApprovedExamples {
struct CreateUsers: Migration {
    static let id = "1791129600_create_users"

    var change: MigrationPlan {
        CreateTable("users") { table in
            table.column("id", .uuid)
                .primaryKey()
                .default(.sql("gen_random_uuid()"))

            table.column("email", .text).notNull()
            table.column("display_name", .text)
            table.column("active", .boolean).notNull().default(true)

            table.timestamps()
        }

        CreateIndex("users_email_index", on: "users", columns: ["email"])
            .unique()
    }
}

struct ExtendUserProfile: Migration {
    static let id = "1791129601_extend_user_profile"

    var change: MigrationPlan {
        AlterTable("users") { table in
            table.rename("display_name", to: "nickname")
            table.add("bio", .text)
        }
    }
}

struct CreateIssues: Migration {
    static let id = "1791129602_create_issues"

    var change: MigrationPlan {
        CreateTable("issues") { table in
            table.column("id", .uuid)
                .primaryKey()
                .default(.sql("gen_random_uuid()"))

            table.column("author_id", .uuid)
                .notNull()
                .references("users", column: "id", onDelete: .restrict)

            table.column("title", .text).notNull()
            table.column("priority", .integer).notNull().default(0)
            table.check("issues_priority_nonnegative", sql: "priority >= 0")
            table.timestamps()
        }

        CreateIndex("issues_author_id_index", on: "issues", columns: ["author_id"])
    }
}

struct AddEmailConstraint: Migration {
    static let id = "1791129603_add_email_constraint"

    var change: MigrationPlan {
        SQL(
            up: "ALTER TABLE users ADD CONSTRAINT users_email_present CHECK (btrim(email) <> '')",
            down: "ALTER TABLE users DROP CONSTRAINT users_email_present"
        )
    }
}

struct ReplaceLegacyLabels: Migration {
    static let id = "1791129604_replace_legacy_labels"

    var change: MigrationPlan {
        Reversible {
            DropTable("legacy_labels")
        } down: {
            CreateTable("legacy_labels") { table in
                table.column("name", .text).notNull()
            }
        }
    }
}

struct NormalizeEmail: Migration {
    static let id = "1791129605_normalize_email"

    var change: MigrationPlan {
        Irreversible("The original spelling of email addresses is not retained") {
            SQL("UPDATE users SET email = lower(email)")
        }
    }
}
}

@Test("Approved documentation examples compile through the public API")
func approvedDocumentationExamples() throws {
    _ = try MigrationCompiler.prepare(ApprovedExamples.CreateUsers())
    _ = try MigrationCompiler.prepare(ApprovedExamples.ExtendUserProfile())
    _ = try MigrationCompiler.prepare(ApprovedExamples.CreateIssues())
    _ = try MigrationCompiler.prepare(ApprovedExamples.AddEmailConstraint())
    _ = try MigrationCompiler.prepare(ApprovedExamples.ReplaceLegacyLabels())
    _ = try MigrationCompiler.prepare(ApprovedExamples.NormalizeEmail())
}
