# IssueTracker acceptance application

A small Peregrine 1.2.0 HTTP application consuming this checkout through Spectro's public API. Projects and issues deliberately share IDs, timestamps, and custom `display_name` columns so joined reads exercise the mapping contract.

From the Spectro repository root:

```sh
python3 scripts/acceptance.py
```

Build and run acceptance with Swift 6.3+ (Peregrine's ESW dependency requires it), an Xcode 26.3+ SDK, Python 3, PostgreSQL client tools (`psql`), and a running PostgreSQL server. The build host must meet [the selected Xcode's system requirements](https://developer.apple.com/xcode/system-requirements/) (macOS 15.6+ for Xcode 26.3); the example package's deployment target is macOS 14. Select that Xcode with `DEVELOPER_DIR` or `xcode-select`: installing a newer Swift toolchain alone leaves an older selected SDK in place, which fails to compile `Data.bytes` in Peregrine's configuration dependency. Spectro itself still supports Swift 6.0 on Linux. Keep the checkout directory named `Spectro` so SwiftPM's local dependency identity overrides Peregrine's transitive Spectro dependency.

Peregrine 1.2.0 currently blocks this HTTP example on Linux: [its error handler imports Apple's `os` module](https://github.com/Maartz/swift-peregrine/blob/1.2.0/Sources/Peregrine/ErrorRescue.swift#L5). A Swift 6.3.3/Linux build reproduced that failure. CI runs this HTTP acceptance on macOS and Spectro's full PostgreSQL-backed suite on Linux/Swift 6.0. Switch to a verified Peregrine release with portable logging before adding Linux HTTP acceptance.

The default connection is `localhost:5432`, user/password `postgres/postgres`; override `DB_HOST`, `DB_PORT`, `DB_USER`, and `DB_PASSWORD` as needed. Use a local test server whose role can create databases. The command always generates a unique `spectro_acceptance_*` database, ignores any existing `DB_NAME`, and removes its database and HTTP processes on exit.

The acceptance command verifies:

- Project creation with an initial issue in one transaction, using validated changesets.
- Joined IDs, custom names, timestamps, nullable notes, and an absent optional issue over HTTP.
- Validation errors, UUID casting, and rollback when creating the initial issue fails.
- Two competing requests for the same unique slug: one HTTP 201, one HTTP 409, one persisted project and issue.
- A migration that adds and backfills issue priority after records already exist.
- Server restart, migration rollback/reapply, and preservation of all HTTP-visible data.
- A compiled `IssueTrackerMigrations` executable that adopts both unchanged SQL migrations and adds a Swift `archived` column and partial index, with independent `psql` assertions and another HTTP restart.

Builds use a persistent cache under `~/Library/Caches/spectro-acceptance/` on macOS, with separate directories for this checkout's CLI and HTTP application. Keeping generated bundles outside cloud-synced `Documents` avoids Finder metadata that can cause Apple's code signer to reject them. The first run compiles into this cache; subsequent runs reuse it. Executable locations are obtained from SwiftPM so both build-engine layouts work.

`--build-root /path/to/local/cache` overrides the cache location. `--skip-build` reuses executables from the selected cache. `SPECTRO_CLI_PATH`, `SPECTRO_EXAMPLE_PATH`, and `SPECTRO_EXAMPLE_MIGRATIONS_PATH` can point to prebuilt executables instead. Acceptance database assertions use `psql` independently of the ORM.

The executable's SQL resources under `Sources/IssueTrackerMigrations/LegacySQL` are byte-for-byte copies of `Migrations/`; keep their IDs and contents unchanged. The [Swift migration guide](../../docs/MIGRATIONS.md) describes explicit registration, configuration, and deployment. `python3 scripts/migrations_acceptance.py` at the repository root exercises a separate Swift 6.0 fixture on macOS and Linux without depending on Peregrine.

## Inspect and run the migration executable

From the repository root, on the compatible build host described above:

```sh
swift run --package-path Examples/IssueTracker IssueTrackerMigrations --help
swift run --package-path Examples/IssueTracker IssueTrackerMigrations plan
swift run --package-path Examples/IssueTracker IssueTrackerMigrations plan --direction down
```

These commands need no database configuration, although SwiftPM may resolve dependencies and build first. The registry includes both bundled SQL migrations followed by the Swift `AddIssueArchive` migration.

To apply them to an existing local development database, export its connection settings first:

```sh
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=postgres
export DB_PASSWORD=postgres
export DB_NAME=issue_tracker_dev
swift run --package-path Examples/IssueTracker IssueTrackerMigrations up
swift run --package-path Examples/IssueTracker IssueTrackerMigrations status
swift run --package-path Examples/IssueTracker IssueTrackerMigrations down --step 1
```

After applying all three migrations, the last command removes the Swift archive column and index while retaining the two SQL migrations. Omitting `--step` rolls back all completed migrations. The executable reads process environment and does not automatically read `.env`; these direct product commands do not require `.spectro.json`. See the [CLI reference](../../docs/CLI.md) for every option.

## HTTP routes

Routes are `GET /health`, `GET /projects`, `POST /projects`, and `POST /issues`. This is a local correctness fixture: its intentional transaction-failure response includes the formatted error so acceptance exercises that path. Deploying an application requires its own authentication and public error policy.
