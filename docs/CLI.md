# CLI reference

The Swift migration workflow described here is **unreleased**. Build the CLI from this checkout and use its `SpectroMigrations` product; the published 2.0.0 CLI supports the existing SQL workflow. See [installation](../README.md#installation) and [Swift target setup](MIGRATIONS.md#set-up-a-target).

## Choose a workflow

| Invocation | Migration source | Requirements |
|---|---|---|
| `spectro migrate …` with `.spectro.json` | The registered Swift declarations and bundled SQL of the configured executable | A Swift package and toolchain; database access for `up`, `down`, and `status` |
| `spectro migrate …` without `.spectro.json` | SQL files in `Sources/Migrations/` relative to the current directory | Database access; `plan` requires a Swift target |
| `MyAppMigrations …` | The registry compiled into that executable | Its resource bundles and runtime libraries; database access for `up`, `down`, and `status` |

The launcher searches for `.spectro.json` at the nearest `Package.swift`, stopping at that package boundary. A malformed descriptor or a failed project build is an error. In Swift mode, the launcher runs the selected product through `swift run --package-path …` and forwards arguments, environment, output, signals, and exit status.

The compiled executable can run from any working directory. It does not need `.spectro.json`, a compiler, Mint, or the application's source checkout. See [deployment](MIGRATIONS.md#deploy-a-compiled-artifact) for packaging.

## Commands

| Command | Behavior |
|---|---|
| `spectro database create <name>` | Create a PostgreSQL database. |
| `spectro database drop <name>` | Confirm and drop a database; `--force` skips the prompt. |
| `spectro migrate init --target MyAppMigrations` | Create the Swift migration scaffold and descriptor; print the target to add to `Package.swift`. |
| `spectro generate migration CreateUsers` | Generate a Swift declaration when configured, otherwise a timestamped SQL file. |
| `spectro migrate plan` | Preview every registered migration without connecting to PostgreSQL. Requires a Swift target. |
| `spectro migrate up` | Apply pending migrations in ascending full-ID order. |
| `spectro migrate down --step 1` | Roll back the newest completed migration. **Omitting `--step` rolls back all.** |
| `spectro migrate status` | Read migration status without creating the tracking table. |

The project executable supports `up`, `down`, `status`, and `plan` with the same options. For example, `swift run MyAppMigrations plan` during development and `/path/to/MyAppMigrations up` after deployment. Database creation, scaffolding, and file generation belong to `spectro`.

## Initialization and generation

Run `init` inside the application package. `--target` accepts a PascalCase Swift name, such as `MyAppMigrations`. It creates:

```text
.spectro.json
Sources/MyAppMigrations/
├── EntryPoint.swift
├── Migrations.swift
└── Migrations/
```

Add the printed target to `Package.swift`. The command leaves that manifest unchanged and refuses to overwrite an existing descriptor or target directory.

In Swift mode, generation creates `<sourceDirectory>/Migrations/CreateUsers.swift`. Fill in its operations and add the printed `CreateUsers()` entry to the registry in `Migrations.swift`. The command does not register it automatically. Registered empty declarations fail planning. Initialization and Swift generation do not need database credentials.

In SQL mode, generation creates `Sources/Migrations/<unix_timestamp>_create_users.sql` and writes a pending record to PostgreSQL. **SQL generation requires database access.** Edit both `-- migrate:up` and `-- migrate:down` sections before applying it. The `--username`, `--password`, and `--database` generation options apply only to SQL mode.

## Preview and rollback

```sh
spectro migrate plan
spectro migrate plan --direction down
spectro migrate plan --migration 1791129600_create_users --direction down
spectro migrate down --step 1
```

- `--migration` selects one full ID, including the timestamp and name. Omit it to preview the whole registry.
- `--direction` accepts `up` or `down` and defaults to `up`. Up previews follow ascending IDs; down previews follow descending IDs and each migration's rollback order.
- `plan` shows registered migrations regardless of the database's applied state. It does not load database configuration. Unknown IDs or irreversible down plans fail before printing a partial plan.
- `down --step N` selects the newest `N` completed migrations. Omit `--step` for all; zero rolls back nothing. The Swift executable rejects negative values and handles zero without loading configuration.
- The Swift runner checks the selected rollback history first. A missing or irreversible migration rejects the entire selected batch before changes. Keep all applied migrations in future artifacts.

Here, “offline” means no PostgreSQL connection. Launching a project through SwiftPM can still resolve dependencies and compile it. Planning checks migration definitions and statement boundaries; PostgreSQL validates full SQL syntax and schema references during execution.

Each migration and its tracking update share one transaction under the command's advisory lock. A failed migration rolls back its own changes; earlier successful migrations remain committed. Schema rollback does not recover deleted data unless the migration explicitly provides that recovery.

## Database configuration

`--username`, `--password`, and `--database` override the corresponding configured credentials on `up`, `down`, and `status`. Host and port come from configuration.

| Variable | SQL migration commands | Default compiled Swift executable |
|---|---|---|
| `DB_HOST` | `localhost` | `localhost` |
| `DB_PORT` | `5432` | `5432`; must be an integer from 1 to 65535 |
| `DB_USER` | `postgres` | Required unless `--username` is supplied |
| `DB_PASSWORD` | Empty string | Required unless `--password` is supplied; empty is allowed |
| `DB_NAME` | `postgres` | Required unless `--database` is supplied |

Legacy SQL and database commands resolve connection credentials from options first, then `.env` in the **current directory**, then process environment, then defaults. For `database create` and `database drop`, the target name must be supplied as an argument or with `--database`; `DB_NAME` does not select it. These two commands connect through the `postgres` maintenance database.

The compiled Swift executable reads process environment and does **not** automatically read `.env`. Export values before launching it:

```sh
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=postgres
export DB_PASSWORD=postgres
export DB_NAME=myapp_dev
spectro migrate up
```

An application's [custom configuration provider](MIGRATIONS.md#commands-and-configuration) can set TLS, pooling, and its own environment policy. Credential options still override that provider's user, password, and database. Help and planning never call the provider.

## Help and exit status

The development utility `spectro test CreateHTTPEvents` displays the original, snake_case, and PascalCase forms of a string without a database connection.

```sh
spectro --help
spectro migrate --help
spectro help migrate plan
spectro generate migration --help
swift run MyAppMigrations --help
swift run MyAppMigrations down --help
```

`spectro help migrate <command>` displays the launcher's reference without building the project. Inside a configured package, `spectro migrate <command> --help` launches the project's executable to display its help. Both forms avoid database access.

Successful commands and help return zero. Invalid arguments, build failures, and migration failures return a nonzero status. The launcher preserves the child command's status; deployment should stop when the migration executable fails.

For authoring, SQL adoption, and deployment examples, continue with the [Swift migration guide](MIGRATIONS.md). For common setup failures, see [troubleshooting](MIGRATIONS.md#troubleshooting).
