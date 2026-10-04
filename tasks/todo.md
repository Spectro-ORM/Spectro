# Spectro ORM - Current Sprint

## Swift migration distribution and DSL — COMPLETE (2026-10-05)

- [x] Verify main, origin/main, and the 2.0.0 tag resolve to b13c41c.
- [x] Isolate the proposal on codex/migrations-design without changing the main checkout.
- [x] Define package distribution, a consumer migration executable, CLI delegation, and deployment artifacts.
- [x] Propose a PostgreSQL result-builder DSL with automatic and explicit rollback.
- [x] Write the [design proposal](../docs/superpowers/specs/2026-10-04-swift-migrations-design.md) and [implementation plan](../docs/superpowers/plans/2026-10-04-swift-migrations.md).
- [x] Check document links, descriptor JSON, and the Swift syntax of the nine design examples; the six DSL declarations now also compile through public API tests on Swift 6.0 and 6.4.
- [x] User approved the proposed DSL and implementation plan.
- [x] Implement the library, executable contract, CLI, deployment acceptance, and documentation.
- [x] Pass 413 tests on macOS and Linux, copied release artifacts, the compiler-free runtime container, and original plus extended HTTP acceptance.
- [x] Complete the independent whole-branch review; reproduce and fix SQL comment boundaries, CLI test environment assumptions, and down preview ordering, then repeat affected validation.

Implementation remains on the isolated branch. See the [validation report](../docs/superpowers/reports/2026-10-04-swift-migrations-validation.md) and [adoption guide](../docs/MIGRATIONS.md). Hosted CI is configured but has not run for this branch.

## Spectro 2.0.0 release preparation — COMPLETE (2026-10-04)

- [x] Audit changes since 1.2.0 and choose 2.0.0 for the new required `Repo` methods and stricter join behavior.
- [x] Update installation versions and prepare release notes and upgrade guidance.
- [x] Reproduce missing `@Schema` soft-delete filtering, decoding, and JSON with two failing regression tests.
- [x] Complete and review `@SoftDelete` macro integration, including shared acronym-aware column naming, then pass the updated suite.
- [x] Sample a stalled test run: the killed CLI child had exited while `Process.waitUntilExit()` remained blocked.
- [x] Replace async CLI test waits with bounded polling and pass ten consecutive process-termination runs.
- [x] Review release documentation and verify the release candidate locally.
- [x] Correct the Swift 6.0 test-macro compilation failure found by hosted CI by evaluating `kill` before `#require`.
- [x] Replace the legacy CI installer after hosted macOS and Linux tests passed but installation of Swift 6.3 for HTTP acceptance failed; pin the Swiftly-backed action and toolchain patch versions.
- [x] Select the installed Xcode 26.3 SDK for HTTP acceptance after its dependency failed to compile against the runner's default Xcode 16.4 SDK; document the example's SDK requirement.

Verification: 368 tests in 35 suites pass on macOS/Swift 6.4, including the macro soft-delete regression; real HTTP acceptance passes both scenarios. Independent review has no remaining findings. Documentation links and `git diff --check` pass. The sampled process-wait hang and its fix affect the CLI test harness; production migration behavior is unchanged by that repair.

Publication gates: pass hosted macOS/Linux CI and HTTP acceptance, merge to main, verify the merged commit, then publish tag/release 2.0.0. The [GitHub release](https://github.com/Spectro-ORM/Spectro/releases/tag/2.0.0) records the published version; preparation alone does not establish publication or hosted CI success.

## Acceptance build-cache repair — COMPLETE (2026-10-04)

- [x] Reproduce the reported resource-bundle signing failure and isolate FinderInfo as the trigger.
- [x] Move CLI/application scratch directories into a persistent local cache and discover executable paths through SwiftPM.
- [x] Verify the exact acceptance command from the new cache, then cached reuse; review and commit the repair.

Verification: the real codesign command fails with FinderInfo and succeeds on the identical clean temporary bundle. The exact `python3 scripts/acceptance.py` command passes from a fresh external cache and on a warm rerun; `--skip-build` also passes. Both generated NIO resource bundles pass strict signature verification and have no FinderInfo/ResourceFork attributes. A controlled failed build retains exit code 17 without a Python traceback and exits before database work. Independent review found no issues; `git diff --check` passes.

## Join, migration, and application hardening — COMPLETE (2026-10-04)

- [x] Checkpoint the completed correctness fixes on `codex/spectro-hardening` (`f2ab867`).
- [x] Reproduce joined-column collisions and missing-row decoding with real PostgreSQL tests.
- [x] Decode explicit, disjoint join projections; preserve nullable fields, reject malformed rows, and define supported join shapes.
- [x] Reproduce competing migration processes; serialize bootstrap, discovery, up/down, and recording on a reserved session with bounded lock acquisition and cleanup.
- [x] Verify competing CLI processes, process termination, cancellation, lock timeout, and a single-connection pool.
- [x] Add a public-API HTTP consumer with repeatable acceptance coverage for joins, changesets, transactions, competing writes, populated-database migration, and restart.
- [x] Run independent review, macOS tests, Linux tests on the minimum supported Swift version, and the application acceptance command; document results and commit each milestone.

Verification:
- macOS, Swift 6.4, PostgreSQL 18.6: 366 tests in 35 suites, exit 0.
- Linux aarch64, Swift 6.0.3, PostgreSQL 16: 366 tests, exit 0, in isolated Docker containers.
- Public Peregrine 1.2.0 consumer on macOS: real HTTP acceptance passes, including independent psql assertions for transaction rollback, migration column/index removal and reapplication, populated data, concurrent writes, and restart persistence.
- Independent join, migration-lifecycle, and acceptance reviews completed. Review findings were fixed and checked. CI YAML parsing and git diff --check pass; no hosted CI run is claimed.
- Commits: f2ab867 (prior correctness checkpoint), 0a51a5d (joined decoding), 5b28faf (migration ownership and cancellation). Application acceptance and CI are the final milestone.

Compatibility finding: Peregrine's ESW dependency requires Swift 6.3. A separate Linux/Swift 6.3.3 consumer build reaches Peregrine but fails because its published 1.2.0 error handler imports Apple's os module. HTTP acceptance therefore runs on macOS; Linux minimum-version coverage verifies Spectro directly. The sibling Peregrine checkout has ongoing changes and was not modified. A published portable Peregrine release is the next dependency requirement for Linux HTTP acceptance.

## Correctness follow-up — COMPLETE (2026-10-04)

- [x] Reproduce migration DDL escaping rollback in an isolated local database.
- [x] Remove recursive error formatting and distinguish rollback success from failure; restore both disabled transaction tests.
- [x] Execute migration SQL and status updates on the same transaction connection; test failure and retry in both directions, tracking failures, deferred commit failures, and a single-connection pool.
- [x] Correct query binding order when joins follow filters, including typed joins; qualify joined soft-delete filters.
- [x] Validate changeset input types against schema fields before persistence; distinguish Foundation booleans from numbers and persist custom column names through both repositories.
- [x] Honor the supplied TLS configuration; reject invalid TLS settings before allocating NIO threads.
- [x] Make CI propagate the actual swift test exit status; verify the pending shared test-pool refactor.
- [x] Initialize fresh migration databases for up/down while keeping status read-only; cover all three commands through the real CLI.
- [x] Independent review complete with no remaining findings in this change; full PostgreSQL-backed suite passes.

Verification: 352 tests in 34 suites passed, exit 0, using Swift 6.4 on macOS and a fresh local PostgreSQL database. The original CLI CREATE TABLE / division-by-zero reproduction now exits 1 without persisting DDL or tracking; correcting the SQL and retrying, then rolling back, succeeds. Fresh verification databases were removed. `git diff --check` and CI YAML validation passed. At that checkpoint, Linux/Swift 6.0 had not been run locally because Docker was stopped, and joined decoding and concurrent migrations were still pending. Those follow-ups are completed in the hardening milestone above; no hosted CI result is claimed.

## Schema DSL Improvements — COMPLETE

### Phase 1: Column Name Overrides + FK Binding + Macro Refactor (backward compatible)
- [x] Add `columnName: String?` to `Column<T>` and `ForeignKey` — `@Column("display_name")`
- [x] Add `foreignKey: String?` to `HasMany<T>`, `HasOne<T>`, `BelongsTo<T>` — `@HasMany(foreignKey: "author_id")`
- [x] SchemaMacro: extend PropertyInfo, parse wrapper args, dedup ExtensionMacro, update loader FK injection
- [x] SchemaRegistry: `is` → `let as` pattern matching, add `Column<UUID>` case, use `columnName` override
- [x] Tests: column override, FK override, Column<UUID> (8 new tests)

### Phase 2: Generic Primary Keys (breaking for code using bare `ID` type)
- [x] `PrimaryKeyType` protocol with UUID/Int/String conformances
- [x] `PrimaryKeyWrapperProtocol` + `ForeignKeyWrapperProtocol` marker protocols for reflection
- [x] `ID<T: PrimaryKeyType>` and `ForeignKey<T: PrimaryKeyType>` — generic property wrappers
- [x] Repo + GenericDatabaseRepo + Spectro: `id: UUID` → `id: some PrimaryKeyType`
- [x] SpectroLazyRelation loaders: `parentId: UUID` → generic `PK: PrimaryKeyType`
- [x] PreloadQuery: `extractUUID` → `extractPrimaryKey`/`extractPrimaryKeyData`, `[UUID:]` → `[AnyHashable:]`
- [x] SchemaMacro: type-aware `defaultValueExpression`, type-aware `as?` casts in loaders
- [x] SpectroError.notFound: `id: UUID` → `id: String`
- [x] RelationshipLoader.loadBelongsTo: uses query instead of repo.get for PK-agnostic loading
- [x] Tests: 7 unit + 13 integration for Int/String PKs (20 new tests)

### Review Fixes
- [x] Fixed build(from:) dict key — always use prop.name (not columnName override) to match Schema.from(row:)
- [x] Fixed BelongsTo loader injection to use foreignKeyOverride when present
- [x] Fixed SQL injection in test helper (parameterized query)

## Previous Work — COMPLETE

### Workstreams 1-4
- [x] SpectroLazyRelation.load(using:) with stored loaders
- [x] Dead code cleanup
- [x] Upsert + Bulk Insert
- [x] Aggregate Queries (sum/avg/min/max)
- [x] @Schema macro auto-injects loader closures

### SpectroDemo (Hummingbird Blog API)
- [x] Full REST API validated with curl (CRUD + preloading)

## Encodable Schema Conformance — COMPLETE

### Spec: 01-encodable-schema
- [x] `@Schema` macro generates `Encodable` extension with `CodingKeys` + `encode(to:)`
- [x] All `@Column`, `@ID`, `@Timestamp`, `@ForeignKey` properties encoded
- [x] `@Column("custom")` overrides produce the correct JSON key
- [x] Properties without overrides use `snake_case` conversion
- [x] Relationship properties encode only when `.loaded`, omit key when `.notLoaded`
- [x] `@Schema("table", encodable: false)` opt-out skips Encodable generation
- [x] 12 integration tests (scalar types, snake_case keys, column overrides, relationships, opt-out, round-trip)
- [x] Zero regressions — 76 existing tests pass

## Changeset Hardening — COMPLETE

- [x] Extract shared `extractPrimaryKey(from:fieldName:)` into `Core/Extensions/ChangesetHelpers.swift`
- [x] Add `insert(_:Changeset<T>)` and `update(_:Changeset<T>)` as `Repo` protocol requirements (drop `SchemaBuilder` constraint)
- [x] Add Changeset overloads to `TransactionRepo` (direct-SQL path, same as `GenericDatabaseRepo`)
- [x] 8 integration tests: insert/update valid, invalid/empty changeset errors, changeset in transaction commit+rollback

## Feature Sprint — COMPLETE

- [x] Pagination: `Query<T>.page(size:page:)` → `Page<T>` with totalCount, totalPages, hasNextPage, hasPreviousPage
- [x] Changeset error serialization: `ChangesetErrors` (Encodable) + `.errorPayload` on `Changeset`
- [x] `validateUniqueness`: async DB uniqueness check, excludes current record on update
- [x] Soft deletes: `@SoftDelete` wrapper, auto-filter on all/get/query, soft delete() → UPDATE SET deleted_at=NOW(), `.withDeleted()` escape hatch

## Previous Future Work — COMPLETE
- [x] Support user-supplied primary keys in repo.insert() — `includePrimaryKey: Bool` param on insert/upsert/insertAll
- [x] Fix fromSync(row:) to respect @Column("custom_name") overrides
- [x] Test coverage for .constraint(...) conflict target (4 tests: insert/update/selective set/empty set error)
- [x] Type-safe aggregate API — closure-based `.sum { $0.age }` replaces string-based `.sum("age")`
- [x] Grouped aggregates — GROUP BY/HAVING support with `groupedSum`, `groupedAvg`, `groupedMin`, `groupedMax`, `groupedCount`
