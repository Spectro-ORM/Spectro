# Swift migrations: distribution and DSL proposal

Status: proposed design for review; no migration implementation is authorized or included.
Date: 2026-10-04
Baseline: main and the peeled 2.0.0 tag both resolve to b13c41cdda2e73fb2a7000399c7d8f450ab05f0e, verified against origin.
Design branch: codex/migrations-design.
Implementation plan: [task sequence](../plans/2026-10-04-swift-migrations.md).

## Decision

Ship an opt-in SpectroMigrations library product from the existing Spectro Swift package. A consuming application compiles its migrations into a dedicated executable using its resolved Spectro dependency. The installed spectro CLI scaffolds and launches that executable. Production runs the built executable directly.

Provide a PostgreSQL migration DSL using Swift result builders. A migration declares a stable ID and a change property. The DSL produces immutable operations, compiles those into forward and rollback SQL, and uses the same migration execution engine as legacy SQL files.

The first release covers distribution, ordinary transactional schema changes, SQL escape hatches, and rollback. It does not add model-to-database diffing, Swift source interpretation, runtime dynamic loading, automatic registration, arbitrary Swift database callbacks, or nontransactional migrations.

## Baseline facts

- Package.swift exposes SpectroKit, SpectroCommon, and the spectro executable. SpectroKit's importable module is Spectro.
- The minimum Swift tools/language version is 6.0; the package declares macOS 13 and supports Linux.
- CI exercises PostgreSQL 16. Preserve that compatibility; do not require PostgreSQL 18 functions.
- MigrationManager discovers epoch-prefixed SQL files and records their complete basename as schema_migrations.version.
- A reserved database session holds advisory lock 0x5350454354524F. Each migration and its status write share a transaction on that session. The default lock wait is 30 seconds.
- Cancellation closes the reserved session. Discovery of pending work occurs after obtaining the lock.
- The actual generation command is spectro generate migration. Execution commands are spectro migrate up, down, and status.
- The existing rollback flag is --step. Omitting it currently rolls back every available completed migration.
- Spectro already defines a Column property wrapper. The proposed DSL avoids another unqualified Column type.
- The SQL generator currently writes a pending record to the database. The new Swift generator will be offline; the legacy SQL path retains its existing behavior.
- Current SQL loading and execution are private to MigrationManager. Sharing execution requires a bounded extraction, not calling a second pooled connection from inside a migration.

These are source observations at the baseline, not a new test-run claim.

## Distribution and consumer workflow

### Package boundaries

| Component | Dependencies | Responsibility |
|---|---|---|
| SpectroCommon | Foundation only | Shared prepared SQL migration values and source descriptors |
| Spectro | Existing dependencies | SQL discovery/parser, tracking, session lock, transaction execution |
| SpectroMigrations, new library product/module | Spectro, SpectroCommon, existing ArgumentParser package | DSL, compiler, registry, reusable executable command |
| spectro, existing executable | Existing dependencies | Project configuration, scaffolding, child-process launch; existing SQL commands |
| MyAppMigrations, consumer executable | SpectroMigrations | Application migration declarations, registry, configuration |

Spectro does not depend on SpectroMigrations. Do not expose withMigrationSession or TransactionContext lifecycle internals merely to cross a module boundary. The shared runner stays inside Spectro.

The additional product is versioned with Spectro. The app and its migration executable resolve the same dependency graph and commit Package.resolved. Do not duplicate the DSL implementation inside the global CLI.

### Consumer files

~~~text
Package.swift
Package.resolved
.spectro.json
Sources/
  MyApp/
  MyAppMigrations/
    EntryPoint.swift
    Migrations.swift
    Migrations/
      CreateUsers.swift
      ExtendUserProfile.swift
    LegacySQL/                  # only if importing existing SQL history
      1700000000_initial.sql
~~~

The consumer adds an executable target depending on the SpectroMigrations product. If legacy SQL exists, that target declares a copied LegacySQL resource directory. The init command prints the exact manifest fragment; it does not rewrite arbitrary executable Swift in Package.swift.

~~~swift
.executableTarget(
    name: "MyAppMigrations",
    dependencies: [
        .product(name: "SpectroMigrations", package: "Spectro")
    ],
    resources: [.copy("LegacySQL")]
)
~~~

Omit the resources argument for projects without SQL resources. Bundle.module only exists for targets with resources.

The generated EntryPoint.swift contains an @main type, not a file named main.swift:

~~~swift
import SpectroMigrations

@main
enum MyAppMigrations {
    static func main() async {
        await MigrationCommand.main(migrations: MigrationRegistry {
            CreateUsers()
            ExtendUserProfile()
        })
    }
}
~~~

The scaffold puts the registry in Migrations.swift as a static migrations property on an extension of MyAppMigrations, and its entry point passes that value instead. Registration is one explicit line per migration. The generator prints the line to add and its destination; it does not parse and rewrite user-authored Swift. The inline declaration above shows the entire runtime contract.

For an existing SQL history, add this registry entry:

~~~swift
SQLMigrations(bundle: .module, directory: "LegacySQL")
~~~

SQLMigrations resolves the supplied bundle to an explicit directory; runtime discovery never falls back to the current working directory. A missing declared resource is an error.

The CLI project descriptor has one versioned format:

~~~json
{
  "formatVersion": 1,
  "migrations": {
    "product": "MyAppMigrations",
    "sourceDirectory": "Sources/MyAppMigrations"
  }
}
~~~

The package root is the descriptor's directory. Product names are nonempty and cannot begin with a dash. Source paths must remain inside that package root. This file contains no credentials and no arbitrary shell commands.

### Commands

| Command | Behavior |
|---|---|
| spectro migrate init --target MyAppMigrations | Scaffold source files and descriptor; print manifest fragment; no database access |
| spectro generate migration CreateUsers | With a descriptor, generate a Swift declaration and stable ID; print registration line; otherwise preserve the SQL generator |
| spectro migrate up | With a descriptor, launch the configured SwiftPM executable and forward up plus arguments |
| spectro migrate down --step 1 | Forward a bounded rollback |
| spectro migrate status | Forward status; no DDL or migration-table bootstrap |
| spectro migrate plan | With a descriptor, preview all registered migrations offline |
| swift run MyAppMigrations up | Direct equivalent without installing the global CLI |
| MyAppMigrations up | Execute the deployed binary without SwiftPM or a compiler |

For a configured Swift project, a malformed descriptor, missing target, or failed build is an error. Never silently fall back to SQL discovery.

The launcher uses Process with an argument array, inherits streams/environment, sets an explicit package root, propagates exit status, and forwards termination to the child. No shell interpolation. The global CLI must resolve Swift-project dispatch before loading its legacy database configuration. Keep this launch contract small: the child owns command semantics and database configuration.

The new binary uses --step with the current meaning: absent means all, zero is a no-op, negative is rejected. This preserves command behavior when projects adopt the new target. Documentation prominently demonstrates --step 1.

Offline plan prints all registered migrations unless --migration ID selects one. --direction up is the default; --direction down previews rollback. It never claims its output is the database's pending set. Unknown IDs and irreversible selected rollback plans fail with a nonzero exit.

MigrationCommand loads database configuration lazily for up/down/status. Default configuration uses process DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, and DB_NAME, with --username, --password, and --database taking precedence. It is strict about invalid ports/missing required values. It does not automatically read .env files. A caller can supply a @Sendable configuration closure returning the existing DatabaseConfiguration, including TLS settings; command overrides then preserve its other settings. Legacy SQL CLI configuration precedence is preserved. Consumer documentation explicitly describes this adoption difference.

### Deployment

Build the app and migration executable from the same revision and dependency resolution for the target platform. Ship the migration binary, required runtime libraries, and any SwiftPM resource bundles together. Run migrations in a dedicated deployment step and propagate failure before starting the rollout.

Acceptance must copy the artifacts out of the checkout, run from an unrelated directory, and exercise the executable with no Swift compiler, SwiftPM, Mint, or source files available. A macOS build is not a Linux deployment artifact.

Keep legacy SQL contents and IDs unchanged when packaging them as resources. Do not replace an applied SQL migration with a newly invented Swift ID. SQL and Swift entries share one ledger, sort order, lock, and transaction engine.

## Proposed DSL

All examples are proposed API usage; they are not implemented or type-checked against a published library.

### Create a table and index

~~~swift
import SpectroMigrations

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
~~~

Migration.change carries a result-builder requirement, so consumers do not need an attribute on every property. CreateTable takes a table-building context; its methods return immutable definitions. They do not issue queries.

The context makes creation and alteration vocabulary distinct and avoids conflicting with Spectro.Column when both modules are imported.

No implicit primary key is added. PostgreSQL defaults to nullable columns; .notNull() is explicit and .primaryKey() implies it. UUID defaults are explicit. gen_random_uuid() works with the existing PostgreSQL 16 baseline.

### Add and rename columns

~~~swift
struct ExtendUserProfile: Migration {
    static let id = "1791129601_extend_user_profile"

    var change: MigrationPlan {
        AlterTable("users") { table in
            table.rename("display_name", to: "nickname")
            table.add("bio", .text)
        }
    }
}
~~~

This rolls back by dropping bio and renaming nickname back to display_name. Changes inside one AlterTable retain declaration order; rollback reverses that order as well as the order of top-level operations.

### References and constraints

~~~swift
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
~~~

References do not implicitly create indexes. Their default constraint name is table_column_fkey, with an optional name argument for an explicit name. Database identifiers are quoted independently from trusted SQL expressions. A schema argument is separate from a name, for example CreateTable("events", schema: "audit"); a dot inside a plain identifier is not interpreted as qualification.

### Raw SQL and explicit rollback

For a database feature outside the typed vocabulary:

~~~swift
struct AddEmailConstraint: Migration {
    static let id = "1791129603_add_email_constraint"

    var change: MigrationPlan {
        SQL(
            up: "ALTER TABLE users ADD CONSTRAINT users_email_present CHECK (btrim(email) <> '')",
            down: "ALTER TABLE users DROP CONSTRAINT users_email_present"
        )
    }
}
~~~

For explicit forward/backward operation lists:

~~~swift
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
~~~

Reversible evaluates the selected branch in its declared order. The framework does not infer the inverse of either branch. The author guarantees the stated schema rollback; recreating the table does not restore its former rows.

A deliberate data transformation can state that it has no rollback:

~~~swift
struct NormalizeEmail: Migration {
    static let id = "1791129605_normalize_email"

    var change: MigrationPlan {
        Irreversible("The original spelling of email addresses is not retained") {
            SQL("UPDATE users SET email = lower(email)")
        }
    }
}
~~~

Unpaired SQL or a destructive operation at the top level is rejected during planning unless wrapped in Reversible or Irreversible. Do not silently treat missing rollback SQL as a no-op. Existing SQL-file empty-down behavior remains a documented legacy exception for compatibility.

### Initial vocabulary and defaults

| Area | Included |
|---|---|
| PostgreSQL types | uuid, text, varchar(length:), integer, bigint, boolean, timestamptz, jsonb, numeric(precision:scale:) |
| Tables | CreateTable, DropTable, named checks, explicit schema argument |
| Columns | column/add, primaryKey, notNull, default, references; rename |
| Indexes | Named B-tree indexes, compound columns, unique, whereSQL for a partial index |
| Helpers | timestamps with explicit names/types defined below |
| Control | Reversible, Irreversible, paired SQL, branch-only unpaired SQL |
| Authoring | Concrete MigrationPlan, result builders, explicit registry |

- Scalar defaults accept string, integer, finite floating-point, and Boolean literals. Strings are SQL literals, never expressions. .sql(...) explicitly opts into a trusted expression. Decimal defaults requiring exact precision use an explicit SQL expression in this release.
- timestamps expands to created_at and updated_at, both TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP. It does not create a trigger and does not refresh updated_at on update.
- Names are explicit historical database names. Do not infer names/types from @Schema, key paths, current model metadata, or mutable global conventions.
- The first typed API supports one primary-key column. Composite keys, type modification, arrays, extensions, triggers, and specialized indexes remain available through explicit SQL.
- No automatic IF EXISTS/IF NOT EXISTS or CASCADE is added.
- Migration bodies and registry assembly must be deterministic. Swift's type system does not enforce purity; documentation and review prohibit environment/time/database-dependent schema declarations. Bodies are evaluated once per command.
- Compilation validates DSL structure, identifiers, and option combinations, not whether objects already exist or application data satisfy constraints.

## Compilation and execution

### Data path

~~~text
Consumer Swift source
    -> MigrationPlan (immutable operations)
    -> MigrationCompiler
    -> PreparedMigration (forward SQL + rollback SQL/reason)
                                      \
Legacy SQL resource directory --------> MigrationCatalog
                                           -> MigrationRunner in Spectro
                                           -> existing reserved database session
~~~

PreparedMigration, MigrationRollback, and MigrationSource live in SpectroCommon. MigrationRollback distinguishes .sql(String) from .irreversible(reason: String). A MigrationSource is either a SQL directory URL or already prepared definitions. There are no escaping database closures in these values.

MigrationCatalog, in Spectro, loads SQL resources with the existing marker/parser rules, validates duplicate full IDs across sources, and produces the same lexical ordering as 2.0.0. DSL IDs follow epoch_seconds_lower_snake_case; the generator assigns them once. Do not reinterpret historical IDs or reorder them by registry order.

MigrationRunner owns shared discovery/tracking/execution. MigrationManager keeps its public file-based API and delegates to this engine. Its discoverMigrations/getPendingMigrations/getAppliedMigrations methods keep returning MigrationFile values.

Use a new error type for new planning/catalog diagnostics. Do not add required members to existing protocols or casually extend existing public enums in a purportedly additive release.

### Reversal rules

| Forward operation | Derived rollback |
|---|---|
| CreateTable | Drop that table, with no cascade |
| Add column | Drop that column |
| Rename column | Rename new name to old name |
| CreateIndex | Drop that named index in its schema |
| SQL(up:down:) | Use the supplied down SQL |
| Reversible | Use the supplied down operation list |
| Irreversible | Reject a selected rollback with its reason |

Expand timestamp helpers before deriving inverses. For nested alterations, reverse the expanded operation sequence. A failed implicit inverse does not trigger a destructive cascade retry.

Validate all selected rollback entries before executing the first one. For the new catalog runner, an applied migration needed by the requested rollback but missing from the artifact causes a clear failure. It must not skip the missing version and roll back an older migration instead. Keep the legacy facade's historical selection behavior unchanged; test this boundary explicitly.

A migration's declared rollback may be known even though it would discard data. SQL preview shows the statements; the library makes no data-recovery claim.

### Transaction boundary

All first-release migrations are transactional. Keep the existing advisory lock identity, 30-second default timeout, reserved-session ownership, cancellation behavior, and atomic migration/status update. Do not execute through a fresh pooled connection inside that session.

The new prepared-migration path rejects top-level transaction-control statements in supplied SQL, including transaction-ending aliases and two-phase transaction commands. BEGIN inside a quoted procedural body is not a top-level transaction command. Preserve the legacy SQL facade's compatibility behavior; authors of legacy files remain responsible for not taking over transaction control.

Nontransactional commands such as CREATE INDEX CONCURRENTLY are not part of this release. Raw SQL is not a workaround for PostgreSQL transaction restrictions. A future transaction opt-out needs a separate recovery/ledger design because it cannot provide the current all-or-nothing guarantee.

## Validation and delivery

The implementation plan defines these gates:

1. All existing SQL migration/CLI behavior remains covered.
2. A public consumer using only SpectroMigrations compiles on Swift 6.0, macOS and Linux.
3. Creation, alteration, foreign keys, literal quoting, SQL escapes, and inverse ordering are checked against PostgreSQL 16.
4. Mixed SQL/Swift history does not reapply historical IDs; duplicate IDs fail.
5. Failure, cancellation, lock contention, and rollback use the existing single-session guarantees.
6. A built migration artifact runs away from the source checkout with its resource bundle and without build tools.
7. New init/generation/plan paths require no database credentials or connection.
8. Update README, migration guide, CLI help, and the acceptance example only when the feature is implemented.

Treat an additive 2.x release as the intended compatibility classification, subject to the final public-API audit. This design does not change the existing 2.0.0 tag or authorize publication.

## Alternatives considered

- Fluent-style asynchronous prepare/revert methods: straightforward, but mix operation declaration with I/O and require handwritten rollback everywhere. The result-builder plan supports preview and reversal with fewer side effects.
- Swift declarations exported to SQL during CI: viable when SQL must be the deployment artifact, but would create a second generated artifact to keep synchronized. The agreed direction is a compiled consumer executable.
- @Migration macros and automatic source discovery: reduce registration boilerplate but add compiler-plugin/code-generation work before the execution contract is proved. Keep explicit registration for the initial release.

## Primary references

- [SwiftPM package products](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#product) support the package/product distribution model.
- [Swift result builders, SE-0289](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0289-result-builders.md) support declarative builders and builder-annotated protocol requirements.
- [Ecto migration change](https://hexdocs.pm/ecto_sql/Ecto.Migration.html#module-change) is the reference for inferred reversal with explicit SQL pairs.
- [PostgreSQL 16 concurrent indexes](https://www.postgresql.org/docs/16/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY) documents the transaction restriction and possible invalid-index residue.

The Spectro API names and scope above are proposals, not APIs copied from those references.
