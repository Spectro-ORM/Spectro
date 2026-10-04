# Swift Migrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. This document is a proposal; the current user request authorizes planning, not implementation.

**Goal:** Let Spectro consumers author versioned Swift migrations and deploy a project-owned migration executable while retaining the 2.0.0 SQL workflow.

**Architecture:** Add SpectroMigrations as an opt-in product in the existing Swift package. Its builders compile immutable plans into prepared SQL migrations. Extract the existing session-owned migration engine inside Spectro so both legacy SQL files and consumer executables share locking, tracking, and transactional execution.

**Tech Stack:** Swift 6.0, SwiftPM, Swift result builders, existing ArgumentParser/PostgresKit/SQLKit dependencies, Swift Testing, PostgreSQL 16.

**Spec:** [distribution and DSL design](../specs/2026-10-04-swift-migrations-design.md).

**Baseline:** main = origin/main = 2.0.0 peeled commit = b13c41cdda2e73fb2a7000399c7d8f450ab05f0e. Work is isolated on codex/migrations-design. No source changes or runtime validation have been performed for this proposal.

## Global Constraints

- The minimum Swift tools/language version is 6.0; the package declares macOS 13 and supports Linux.
- CI exercises PostgreSQL 16. Preserve that compatibility; do not require PostgreSQL 18 functions.
- Spectro does not depend on SpectroMigrations.
- All first-release migrations are transactional.
- Keep the existing advisory lock identity, 30-second default timeout, reserved-session ownership, cancellation behavior, and atomic migration/status update.
- No automatic IF EXISTS/IF NOT EXISTS or CASCADE is added.
- Names are explicit historical database names.
- Keep legacy SQL contents and IDs unchanged when packaging them as resources.
- Do not add required members to existing protocols or change existing public return types.
- The standalone SQL CLI and MigrationManager facade preserve 2.0.0 behavior.
- New Swift init, generation, help, and offline plan commands do not connect to a database.
- No implementation, version bump, remote push, or release publication is authorized by this plan.

## Review Focus

1. A mixed catalog contains duplicate IDs or an applied migration absent from the deployment artifact: reject ambiguity and do not roll back an older migration in its place. Tasks 1 and 6 own these tests.
2. An identifier or literal contains quotes, a Unicode name exceeds PostgreSQL's identifier limit, or the same modifier appears twice: quote correctly or reject before DDL. Tasks 2 and 3 own these tests.
3. Rollback crosses multiple operations inside AlterTable or an explicit Reversible branch: preserve the defined inverse ordering and avoid partial rollback before an irreversible entry. Tasks 2 and 3 own these tests.
4. The executable runs outside the source checkout with no compiler or database credentials for plan: resources must resolve and configuration must remain lazy. Tasks 4 and 6 own these tests.
5. The installed CLI has a different version from the project's Spectro dependency or its child fails/receives termination: execute the project-owned runtime, retain the child's exit status, and release migration ownership. Tasks 5 and 6 own these tests.

## File map

| Path | Responsibility |
|---|---|
| Sources/SpectroCommon/Types/PreparedMigration.swift | Immutable version, name, forward SQL, rollback disposition |
| Sources/SpectroCommon/Types/MigrationSource.swift | SQL directory or prepared migration array |
| Sources/SpectroCommon/Enums/MigrationRollback.swift | Explicit SQL rollback or irreversible reason |
| Sources/SpectroCommon/Types/MigrationPlanningError.swift | New diagnostic with migration ID, operation position, and reason |
| Sources/Spectro/Core/Migration/MigrationCatalog.swift | Discover/load sources, duplicate checks, lexical ordering |
| Sources/Spectro/Core/Migration/MigrationRunner.swift | Shared migration execution lifecycle |
| Sources/Spectro/Core/Migration/MigrationManager.swift | Existing public SQL facade |
| Sources/Spectro/Core/Migration/SQLStatementParser.swift | Existing SQL splitting; targeted fixes only when new adversarial fixtures expose a bug |
| Sources/SpectroMigrations/Migration.swift | Migration protocol |
| Sources/SpectroMigrations/MigrationPlan.swift | Value-based operation representation |
| Sources/SpectroMigrations/Builders/MigrationBuilder.swift | Top-level and explicit-branch result builder |
| Sources/SpectroMigrations/Builders/TableBuilder.swift | Table elements and creation context |
| Sources/SpectroMigrations/Builders/AlterTableBuilder.swift | Alteration elements and context |
| Sources/SpectroMigrations/Operations/Tables.swift | CreateTable and DropTable |
| Sources/SpectroMigrations/Operations/Columns.swift | Column/addition definitions, defaults, references, timestamps |
| Sources/SpectroMigrations/Operations/Indexes.swift | Named B-tree index definitions |
| Sources/SpectroMigrations/Operations/Control.swift | Reversible, Irreversible, and SQL |
| Sources/SpectroMigrations/Compilation/MigrationCompiler.swift | Validation, expansion, inverse construction |
| Sources/SpectroMigrations/Compilation/PostgresMigrationRenderer.swift | Identifier/literal/expression SQL rendering |
| Sources/SpectroMigrations/Registry/MigrationRegistry.swift | Explicit registration, DSL snapshots, SQL resource sources |
| Sources/SpectroMigrations/Command/MigrationCommand.swift | Reusable runner command and process entry point |
| Sources/SpectroMigrations/Command/MigrationCommandArguments.swift | up/down/status/plan argument parsing |
| Sources/SpectroMigrations/Command/MigrationCommandConfiguration.swift | Environment/CLI configuration, lazy connection creation |
| Sources/SpectroCLI/Migration/MigrationProject.swift | .spectro.json decoding, validation, path resolution |
| Sources/SpectroCLI/Migration/MigrationProjectLauncher.swift | Argument-array process launch and exit/signal forwarding |
| Sources/SpectroCLI/Migration/SwiftMigrationGenerator.swift | Offline declaration generation; prints registration line |
| Sources/SpectroCLI/Commands/Migration/Init/InitializeMigrations.swift | Source/descriptor scaffolding and manifest fragment |
| Tests/SpectroMigrationsTests/ | Public DSL/compiler/command unit tests |
| Tests/SpectroTests/MigrationTests/MigrationRunnerTests.swift | PostgreSQL-backed mixed-catalog execution regression tests |
| Tests/Fixtures/SwiftMigrationsConsumer/ | Standalone Swift 6.0 public-API consumer and bundled SQL |
| scripts/migrations_acceptance.py | Portable consumer/deployment acceptance |
| docs/MIGRATIONS.md | Published feature and adoption guide, written at implementation time |

Do not move unrelated ORM, Changeset, query, or schema code. MigrationCommand can depend on the existing ArgumentParser package without importing Noora. The global CLI retains its current presentation.

## Shared contract

The following signatures specify the cross-task boundaries. Their bodies are implementation work.

~~~text
SpectroCommon:
  PreparedMigration(version: String, name: String,
                    upSQL: String, rollback: MigrationRollback)
  MigrationRollback.sql(String)
  MigrationRollback.irreversible(reason: String)
  MigrationSource.sqlDirectory(URL)
  MigrationSource.prepared([PreparedMigration])
  MigrationPlanningError(migrationID: String?,
                         operationIndex: Int?, reason: String)
  All above values are Sendable; PreparedMigration and errors expose
  their declared fields as immutable public properties.

Spectro:
  MigrationCatalog.load(sources: [MigrationSource]) throws -> [PreparedMigration]
  MigrationRunner.init(connection: DatabaseConnection,
                       sources: [MigrationSource],
                       lockTimeout: Duration = .seconds(30))
  MigrationRunner.runMigrations() async throws
  MigrationRunner.runRollback(steps: Int? = nil) async throws
  MigrationRunner.getMigrationStatus() async throws -> [MigrationRecord]

SpectroMigrations:
  protocol Migration: Sendable
    static var id: String { get }
    @MigrationBuilder var change: MigrationPlan { get }

  MigrationCompiler.prepare<M: Migration>(_ migration: M) throws
      -> PreparedMigration
  MigrationRegistry.init(@MigrationRegistryBuilder _ content: () -> MigrationEntries)
  MigrationRegistry.sources() throws -> [MigrationSource]
  SQLMigrations.init(bundle: Bundle, directory: String)

  MigrationCommand.run(arguments: [String], migrations: MigrationRegistry,
    configuration: (@Sendable () throws -> DatabaseConfiguration)? = nil)
      async -> Int32
  MigrationCommand.main(migrations: MigrationRegistry,
    configuration: (@Sendable () throws -> DatabaseConfiguration)? = nil)
      async
~~~

The default nil configuration provider resolves process environment plus the optional --username, --password, and --database command overrides. Validate the port. A custom provider is invoked only for a database command; command overrides are then applied without dropping its TLS or pool settings. Neither branch automatically loads .env.

The registry evaluates each change body once during assembly, preserving an immutable snapshot. sources() compiles those snapshots rather than invoking the body again. Use an internal compiler entry point taking an ID and captured MigrationPlan so the generic public prepare method and registry share implementation.

Only MigrationPlan and the DSL's necessary public value types cross builder boundaries. Keep its internal operation enum private to the new module. Public MigrationStep values can expose a plan value without exposing the enum. Table and alteration builders use different element collections and contexts.

MigrationManager keeps all its current public signatures, defaults, return values, status-table behavior, and legacy rollback selection. Add an internal execution policy used only by that facade if strict missing-history checks differ from the new runner.

---

## Task 1: Share the SQL execution engine without changing the SQL API

**Deliverable:** Current SQL migrations still work through MigrationManager; a new runner can execute prepared definitions and SQL directories under the same lifecycle.

**Files:** New SpectroCommon values and Spectro MigrationCatalog/MigrationRunner from the file map; modify MigrationManager.swift. Add MigrationRunnerTests.swift. Retain MigrationManagerTests.swift and CLITests.swift as regression gates.

**Consumes:** Existing DatabaseConnection.withMigrationSession, SQLStatementParser, MigrationFile, MigrationRecord, MigrationStatus, and current facade behavior.

**Produces:** All SpectroCommon and Spectro contracts in Shared contract.

- [ ] Add pure catalog tests for a prepared definition, an SQL directory, both sources combined, duplicate IDs, empty forward SQL, and unchanged lexical ordering. Use full legacy IDs, including two distinct names with the same timestamp.

Representative prepared value:

~~~swift
let migration = PreparedMigration(
    version: "1700000001_add_priority",
    name: "add_priority",
    upSQL: "ALTER TABLE issues ADD COLUMN priority INTEGER NOT NULL DEFAULT 0",
    rollback: .sql("ALTER TABLE issues DROP COLUMN priority")
)
let catalog = try MigrationCatalog.load(sources: [.prepared([migration])])
#expect(catalog.map(\.version) == ["1700000001_add_priority"])
~~~

- [ ] Run the new focused tests before adding types; compilation should fail on the absent contract.
- [ ] Add the immutable common values and new diagnostic type. Do not edit the existing MigrationError enum.
- [ ] Reject top-level transaction control in new prepared SQL after statement splitting: BEGIN, START TRANSACTION, COMMIT, END, ROLLBACK, ABORT, SAVEPOINT, RELEASE, and PREPARE TRANSACTION. Inspect tokens outside leading comments, not substrings inside quoted SQL. Test a rejected COMMIT and an accepted dollar-quoted procedural BEGIN. Preserve the legacy SQL-directory facade behavior.
- [ ] Extract source loading/SQL parsing into MigrationCatalog and the session lifecycle into MigrationRunner. Keep the reserved session implementation in DatabaseConnection unchanged unless a reproduced regression requires a fix.
- [ ] Make the legacy facade delegate execution while preserving public file-based discovery/status methods and existing insertMigrationRecord behavior.
- [ ] Add PostgreSQL regressions using the existing serialized DatabaseIntegrationTests fixture style: prepared up failure rolls back DDL/tracking; down failure preserves completed status; deferred commit failure remains atomic; one-connection pools complete up/down/up.
- [ ] Add mixed SQL/prepared contention, bounded lock timeout, cancellation, and retry cases. Assert schema and ledger contents with a separately acquired connection after the migration session ends.
- [ ] Test strict rollback history: apply A and B, build a new artifact containing only A, request one rollback, expect missing B and unchanged schema/ledger. Pin legacy facade behavior separately.
- [ ] Test rollback preflight: a selected batch containing an irreversible migration causes no migration in that batch to execute. An irreversible migration outside the selected batch does not block a bounded rollback.
- [ ] Run the focused suites, then review the moved lock, cancellation, and commit code against the 2.0.0 version.

~~~sh
swift test --filter MigrationManagerTests
swift test --filter MigrationRunnerTests
swift test --filter CLITests
git diff --check
~~~

- [ ] Commit the engine extraction with its regression tests.

## Task 2: Add the package product and a small reversible builder/compiler

**Deliverable:** A public consumer can declare and preview CreateTable, AlterTable.add/rename, CreateIndex, timestamps, and literal/default options without a database.

**Files:** Package.swift; the new Migration, Plan, builders, Tables/Columns/Indexes, and compiler/renderer files; Tests/SpectroMigrationsTests/BasicMigrationTests.swift and RenderingTests.swift.

**Consumes:** PreparedMigration and MigrationRollback from Task 1.

**Produces:** Migration protocol, builder contracts, MigrationCompiler.prepare, and ordinary operations from the design.

- [ ] Add the SpectroMigrations library product/target and SpectroMigrationsTests target. The new target depends on Spectro and SpectroCommon; add ArgumentParser when Task 4 needs it. Keep the Swift 6.0/macOS 13 floor.
- [ ] Add a test declaring the exact CreateUsers example from the spec through a public import. Verify its forward SQL creates the declared fields and index and its rollback drops the index before the table.
- [ ] Include a source-compatibility test file importing both Spectro and SpectroMigrations. Its table.column calls must compile alongside an ORM @Column declaration.
- [ ] Implement value-based builders and pure compilation. Evaluate builder closures immediately; store value operations, not escaping closures.
- [ ] Render identifiers and literals with independent functions. Use the existing identifier quoting helper where appropriate, after inspecting its behavior; never use literal escaping for identifiers or vice versa.
- [ ] Reject empty/NUL identifiers and identifiers exceeding PostgreSQL's normal 63-byte limit. Reject duplicate column names, duplicate modifier assignments, invalid varchar/numeric sizes, nonfinite floating defaults, empty index columns, and more than one typed primary-key column.
- [ ] Make string defaults produce SQL strings and .sql defaults produce trusted expressions. Timestamps expand to the exact documented columns/defaults before reverse-plan construction.
- [ ] Add the nested-order test below.

~~~swift
struct ExtendProfile: Migration {
    static let id = "1700000002_extend_profile"

    var change: MigrationPlan {
        AlterTable("users") { table in
            table.rename("display_name", to: "nickname")
            table.add("bio", .text)
        }
    }
}

let prepared = try MigrationCompiler.prepare(ExtendProfile())
guard case .sql(let down) = prepared.rollback else {
    Issue.record("Expected a derived rollback")
    return
}
let drop = try #require(down.range(of: "DROP COLUMN"))
let rename = try #require(down.range(of: "RENAME COLUMN"))
#expect(drop.lowerBound < rename.lowerBound)
~~~

- [ ] Check exact SQL for names containing a double quote, the reserved word order, an apostrophe in a default such as O'Reilly, a backslash, an empty string, and separately qualified schemas. Do not split a dot inside a plain identifier. Verify string defaults under both values of standard_conforming_strings; use an explicit PostgreSQL escape-string rendering strategy if ordinary quoting would depend on that setting.
- [ ] Add compiler diagnostics that include migration ID and zero-based operation position; test those fields instead of depending only on string substrings.
- [ ] Run the new pure suite with no DB_* variables required and build an external fixture target through the public product on Swift 6.0.
- [ ] Review the first example's readability and public API footprint; commit only this first vocabulary.

## Task 3: Complete explicit rollback, SQL, references, and checks

**Deliverable:** Authors can express references/constraints and explicitly handle operations whose inverse cannot be inferred.

**Files:** Operations/Control.swift; extend Columns.swift, Indexes.swift, compiler/renderer; add ControlFlowTests.swift and ConstraintTests.swift; extend MigrationRunnerTests.swift.

**Consumes:** MigrationStep/Plan and the compiler pipeline from Task 2.

**Produces:** Reversible, Irreversible, SQL(up:down:), branch-only SQL(String), references, named checks, and partial named B-tree indexes.

Public operation forms:

~~~text
Reversible.init(@MigrationBuilder up: () -> MigrationPlan,
                @MigrationBuilder down: () -> MigrationPlan)
Irreversible.init(_ reason: String,
                 @MigrationBuilder _ body: () -> MigrationPlan)
SQL.init(up: String, down: String)
SQL.init(_ sql: String)
ColumnDefinition.references(_ table: String, schema: String? = nil,
  column: String = "id", onDelete: ReferenceAction = .noAction,
  name: String? = nil) -> ColumnDefinition
ReferenceAction: noAction, restrict, cascade, setNull, setDefault
CreateIndex.whereSQL(_ expression: String) -> CreateIndex
~~~

AddedColumnDefinition provides the same column modifiers, including references. CreateTable's context supplies check(name, sql:). Constraint names are explicit for checks; reference constraint naming is rendered consistently with the declared table/column and validated against identifier length.

- [ ] Add tests for the spec's CreateIssues, paired SQL, Reversible, and Irreversible examples before implementing the missing operations.
- [ ] Implement direction-aware lowering: paired SQL swaps scripts; Reversible selects a branch and evaluates it forward in declaration order; Irreversible produces a reason instead of rollback SQL.
- [ ] Reject unpaired SQL/DropTable outside an explicit branch and reject empty explicit rollback branches. Paired SQL requires meaningful content in both directions.
- [ ] Ensure nested Reversible nodes follow the selected branch without double inversion; reject Irreversible inside an explicit down branch because it cannot provide the declared rollback guarantee.
- [ ] Render references with separate identifiers; validate contradictory local options such as NOT NULL plus ON DELETE SET NULL. Leave cross-table existence/type compatibility to PostgreSQL.
- [ ] Render named checks and partial predicates as explicit trusted expressions. Do not infer foreign-key indexes.
- [ ] Run PostgreSQL integration for FK enforcement, named check rejection, partial unique index behavior, exact persisted default strings, and reversing a multi-operation AlterTable.
- [ ] Add a dollar-quoted function SQL pair with an internal semicolon and an ordinary string containing a semicolon. Use the existing SQL parser; fix it only if the new cases reproduce incorrect statement boundaries.
- [ ] Confirm raw SQL still executes inside a transaction. A concurrent index example should fail with the database restriction and leave no completed ledger entry; do not introduce a hidden transaction opt-out.

~~~sh
swift test --filter SpectroMigrationsTests
swift test --filter SQLStatementParserTests
swift test --filter MigrationRunnerTests
~~~

- [ ] Review inversion and trusted-fragment boundaries; commit this vocabulary separately.

## Task 4: Ship the consumer executable contract and resource registry

**Deliverable:** A separate Swift package builds and runs migration help/plan/status/up/down using only the published product interface.

**Files:** Registry/MigrationRegistry.swift; Command files from the file map; Package.swift for ArgumentParser dependency; Tests/SpectroMigrationsTests/RegistryTests.swift and CommandTests.swift; Tests/Fixtures/SwiftMigrationsConsumer/Package.swift and source/resource files.

**Consumes:** Task 1 runner/catalog, Task 2/3 compiler.

**Produces:** Registry and MigrationCommand signatures from Shared contract.

- [ ] Create a standalone fixture package with tools version 6.0 and a path dependency to Spectro. Define a FixtureMigrations executable with copied LegacySQL resources.
- [ ] Add one legacy SQL migration, one Swift CreateTable migration, and one Swift AlterTable migration with distinct stable IDs. Keep declarations independent of application model types.
- [ ] Implement explicit type registration and SQLMigrations bundle-directory registration. Resolve resource paths from the passed Bundle. Never infer Bundle.main or project-root paths.
- [ ] Test body evaluation once per registry assembly, duplicate IDs across SQL/Swift, missing resource directories, and registration order differing from execution order.
- [ ] Implement the reusable command using ArgumentParser. Parse help/plan first; instantiate configuration and DatabaseConnection only for database commands. Ensure shutdown on success/error.
- [ ] Implement strict environment loading and optional credential overrides as specified in Shared contract. Preserve custom TLS and connection-pool settings when applying overrides.
- [ ] Add this offline regression through the public command function.

~~~swift
struct UnexpectedConfigurationLoad: Error {}

let exitCode = await MigrationCommand.run(
    arguments: ["plan"],
    migrations: MigrationRegistry { CreateUsers() },
    configuration: { throw UnexpectedConfigurationLoad() }
)
#expect(exitCode == 0)
~~~

CreateUsers is the test declaration from the spec, included in the fixture. A separate subprocess test asserts output includes its SQL, contains no pending-state claim, and contains no credentials.

- [ ] Test plan --migration ID --direction down, unknown IDs, all-migrations output, irreversible output, --step 0, negative --step, and default all-rollback behavior.
- [ ] Test status on a fresh database using a role without DDL privileges: empty status succeeds without creating schema_migrations.
- [ ] Test CLI credential overrides supplying otherwise missing required environment values; invalid port fails before connecting. Help/plan succeed with those values absent.
- [ ] Build/run the standalone consumer with Swift 6.0 on macOS and Linux; retain build artifacts outside cloud-synced checkout paths.

~~~sh
swift build --package-path Tests/Fixtures/SwiftMigrationsConsumer --product FixtureMigrations
swift run --package-path Tests/Fixtures/SwiftMigrationsConsumer FixtureMigrations plan
~~~

- [ ] Review the executable's public import/entry point/resource requirements; commit the consumer contract.

## Task 5: Add offline scaffolding and project-aware CLI launch

**Deliverable:** Consumers can initialize a target, generate Swift files, and use spectro migrate commands without duplicating the runtime in the installed CLI.

**Files:** MigrationProject.swift, MigrationProjectLauncher.swift, SwiftMigrationGenerator.swift, InitializeMigrations.swift; SpectroCommand.swift; existing GenerateMigration.swift and migrate action files; Tests/SpectroTests/CLITests/CLITests.swift. Exercise CLI behavior through subprocesses, matching the existing CLI suite.

**Consumes:** Descriptor/command contract in the spec; Task 4 consumer executable.

**Produces:** spectro migrate init, Swift generation mode, configured project dispatch, spectro migrate plan.

- [ ] Add subprocess cases for .spectro.json format 1, malformed JSON, unsupported format version, missing product, source path escaping the package, paths with spaces, and source target name validation.
- [ ] Implement nearest package-root discovery from the invocation directory, bounded at the filesystem root. Resolve the descriptor relative to its Package.swift; do not search unrelated directories.
- [ ] Implement init with a preflight of every destination. Refuse to overwrite existing descriptor/source files. Produce EntryPoint.swift, Migrations.swift, the Migrations directory, descriptor, and a printed executable-target fragment.
- [ ] Keep Package.swift editing manual. Print the exact fragment including product dependency and optional resource rule. Do not claim the target is runnable before that fragment is installed.
- [ ] Implement Swift generation without a database: validate a PascalCase Swift type name, generate its epoch-based stable ID and a file named after the type, refuse overwrite, print the explicit registry addition. An empty generated change body must fail planning with an empty-migration error once registered.
- [ ] Preserve spectro generate migration behavior when no descriptor is present.
- [ ] Launch SwiftPM through Process argument arrays. For a configured product, the logical invocation is:

~~~text
swift run --package-path <descriptor-directory> <product> <command> <arguments>
~~~

The argument array is constructed directly; angle-bracket values here name runtime inputs, not shell substitutions. Do not append database credentials to logs.

- [ ] Route configured projects before legacy DB configuration/connection setup. Give malformed descriptor/build failure a nonzero exit; never fall through to SQL mode.
- [ ] Forward stdout/stderr/stdin, process environment, and child exit status. Avoid blocking Process.waitUntilExit in async tests; use bounded polling or a properly bridged termination handler.
- [ ] Forward SIGINT/SIGTERM to the spawned process group, including the runner launched by SwiftPM. Verify eventual child reaping and that a subsequent runner can acquire the database lock.
- [ ] Test an installed-launcher fixture against two project runtime fixtures whose plan outputs differ. The selected project's output must win; the launcher contains no copied DSL behavior.
- [ ] Run old CLITests plus the new init/generate/delegation cases. A stub swift executable on a controlled test PATH can record arguments and return a chosen exit code; do not create shell-command configuration in the product.
- [ ] Review CLI error messages and the one-time manifest/registration steps; commit the CLI integration.

## Task 6: Prove the deployment artifact and mixed-history lifecycle

**Deliverable:** A project migration executable and resources can be deployed independently of the source checkout and build tooling.

**Files:** scripts/migrations_acceptance.py; fixture package/resources from Task 4; .github/workflows/ci.yml; extend Examples/IssueTracker/Package.swift and add its migration executable; extend scripts/acceptance.py without removing existing SQL coverage.

**Consumes:** All prior contracts and the unchanged 2.0.0 legacy SQL workflow.

**Produces:** Repeatable isolated PostgreSQL acceptance and CI gates for macOS/Linux.

- [ ] Model the new portable harness on scripts/acceptance.py: unique disposable database, explicit DB_* overrides, bounded subprocess timeouts, cleanup, external build cache, and SwiftPM --show-bin-path lookup.
- [ ] Build FixtureMigrations in release mode for the deployment platform. Copy the executable and required resource bundle into a temporary artifact directory outside the fixture checkout.
- [ ] Execute help and plan from a different working directory with build tools unavailable on PATH and no DB credentials. Confirm SQL resources are still available.
- [ ] In Linux CI, run the copied artifact in a runtime-only container without a Swift compiler, SwiftPM, Mint, or source mounts, with required Swift/system runtime libraries present.
- [ ] Apply the legacy SQL using the 2.0.0-compatible file workflow, then run the mixed consumer. Assert its old ID remains one ledger row and its SQL is not reapplied.
- [ ] Assert the populated-database sequence up -> down --step 1 -> up changes and restores the intended column/index while preserving existing rows.
- [ ] Start two independent consumer binaries against one fresh database and assert each migration runs once. Terminate a process during its owned migration and assert another process succeeds without a stranded advisory lock.
- [ ] Run an artifact missing the most recently applied migration and request down --step 1; it must report the missing ID and change nothing.
- [ ] Add a separate registry with duplicate SQL/Swift IDs; it must fail without applying either copy.
- [ ] Keep the existing HTTP acceptance scenario, and add a scenario using an IssueTrackerMigrations target. Validate the added Swift migration through independent psql assertions and an HTTP restart.
- [ ] Run the portable migration consumer on Linux/Swift 6.0/PostgreSQL 16. Keep Peregrine HTTP acceptance on the existing macOS/Swift 6.3.3/Xcode 26.3 setup; do not make the ORM's minimum floor depend on that example.

~~~sh
python3 scripts/migrations_acceptance.py
python3 scripts/acceptance.py
swift test --jobs 4
git diff --check
~~~

Use the scripts' explicit build-root options for paths outside synced Documents folders. Do not claim hosted CI passes based only on local results.

- [ ] Review artifact completeness and platform-specific process behavior; commit acceptance and CI changes.

## Task 7: Document adoption and audit the additive release

**Deliverable:** Consumers have accurate installation, authoring, deployment, rollback, and existing-SQL adoption documentation.

**Files:** README.md, docs/MIGRATIONS.md, Examples/IssueTracker/README.md, tasks/todo.md; update relevant instruction files only if tracked and applicable. Add a changelog entry when implementation is validated.

**Consumes:** The implemented public API and the acceptance evidence from Task 6.

**Produces:** Reviewable release documentation and an explicit compatibility assessment; no automatic publication.

- [ ] Write the exact SwiftPM product/target setup, .spectro.json, entry point, registration, generation, local launch, and release-artifact commands using the final tested names.
- [ ] Include the DSL examples from the design only after compiling them in the public consumer tests.
- [ ] Explain the epoch/full-ID ledger contract, mixed-history adoption, resource packaging, process-environment configuration, --step default, timestamps behavior, and schema-only versus data-recovering rollback.
- [ ] State that plan is offline/all-registered, bodies must be deterministic, raw SQL uses the same transaction, and concurrent indexes are outside the first-release transaction model.
- [ ] Compare the public surface to 2.0.0: no new required protocol members, no changed existing method signatures/defaults, no extra dependency product required for existing SpectroKit users.
- [ ] Review the completed branch independently using the repository's review workflow, fix actionable findings, then rerun only checks affected by fixes.
- [ ] Record actual local/hosted validation and remaining limits. Propose an additive 2.x version only if the audit supports it.
- [ ] Commit documentation. Await the user's implementation/release instructions before any merge, tag, or publication.

## Plan self-review and current validation

- Distribution is covered by Tasks 4-6; DSL semantics by Tasks 2-3; legacy compatibility and lifecycle by Task 1.
- Every Review Focus item has an assigned task and an explicit test scenario.
- The new module has a one-way dependency on Spectro; session ownership never leaves the existing core.
- No optional source-generation plugin, dynamic loader, model diff engine, transaction opt-out, or additional database backend is required.
- Current work consists only of this plan, the design proposal, and a planning-status entry in tasks/todo.md.
- Future implementation must verify these proposed signatures and result-builder inference on Swift 6.0 before treating the examples as working API.
- Planning checks passed: local document links, balanced fences, placeholder scan, descriptor JSON parsing, and syntax parsing of all nine Swift examples in the design. Syntax parsing does not resolve or type-check the proposed API and does not exercise a database.
