# Upgrading to Spectro 2.1

Spectro 2.1 adds Swift migration declarations and a project-owned migration executable. It is an additive update from 2.0: existing `SpectroKit` consumers need no new product dependency, protocol changes, or database rewrite.

## Keep the SQL workflow

Update the Spectro package constraint to `from: "2.1.0"` and the Mintfile to `roost-framework/Spectro@2.1.0`. Check the installed CLI with `spectro --version`.

Without `.spectro.json`, the CLI continues to use `Sources/Migrations` relative to the current directory. `MigrationManager` keeps its API. Keep existing filenames and contents unchanged. SQL migrations still require direct or session-pooled connections and transaction-compatible SQL.

If updating from 1.x, follow the [2.0 upgrade guide](UPGRADING-2.0.md) first for required repository methods and stricter joined-read behavior.

## Opt into Swift migrations

1. Run `spectro migrate init --target MyAppMigrations` in the application package.
2. Add the printed executable target with a `SpectroMigrations` product dependency to `Package.swift`.
3. Include historical SQL as target resources and register it with `SQLMigrations(bundle: .module, directory: "LegacySQL")`.
4. Generate new declarations, fill their bodies, and add their instances to `MigrationRegistry`.
5. Preview with `spectro migrate plan`, inspect database history with `status`, and apply with `up`.

Do not translate applied SQL into new Swift IDs. Both formats use the same full-ID ledger. Keep every applied migration in future artifacts; duplicate IDs and missing rollback history are errors.

The compiled executable reads process environment, not `.env` automatically. The legacy SQL CLI keeps its existing configuration precedence. Omitting `--step` from `down` rolls back all completed migrations.

## Ship the executable

Build the application and migration target from the same revision and `Package.resolved`, on the deployment platform. Copy the release executable, all required resource bundles, and runtime libraries. Run the executable directly in a deployment step; SwiftPM and the installed CLI are development tools.

See the [migration guide](MIGRATIONS.md) for the complete workflow, the [CLI reference](CLI.md) for options, and the [DocC website](../Documentation/README.md) for linked guides and API pages.
