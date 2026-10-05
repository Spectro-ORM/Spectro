# SQL migrations and the shared engine

Keep the existing SQL directory workflow or embed the migration runner in an application.

## Overview

### Use the SQL CLI

Without `.spectro.json`, `spectro` reads SQL migrations from `Sources/Migrations` in the current directory:

```sh
spectro database create myapp_dev
spectro generate migration CreateUsers
spectro migrate up
spectro migrate status
spectro migrate down --step 1
```

Supply connection settings through the CLI's credential options, a `.env` file in the current directory, or process environment. Credential options take precedence over `.env`, which takes precedence over environment and defaults. Database creation takes a name argument or `--database`; `DB_NAME` does not select that command's target database.

Generation writes a timestamped file and records a pending migration, so the SQL generator requires database access. Fill both sections of the generated file:

```sql
-- migrate:up
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL
);

-- migrate:down
DROP TABLE users;
```

The full filename without `.sql` is the migration ID. Keep it stable after applying the file. Omitting `--step` rolls back all completed migrations. Status reads the existing ledger without creating it.

### Use the library facade

```swift
let manager = client.migrationManager(
    migrationsPath: URL(fileURLWithPath: "/app/migrations"),
    lockTimeout: .seconds(30)
)
try await manager.runMigrations()
let status = try await manager.getMigrationStatus()
try await manager.runRollback(steps: 1)
```

``MigrationManager`` preserves the SQL-file API. Its default path is `Sources/Migrations` relative to the current working directory. Prefer an explicit URL in deployed applications.

### Understand execution

Migration commands reserve a PostgreSQL session and acquire an advisory lock before modifying tracking state or selecting work. Use a direct or session-pooled connection; transaction pooling cannot preserve the session lock.

Each migration and its ledger update share a transaction. A failed migration rolls back its own changes; earlier successful migrations remain committed. SQL must be compatible with this transaction model. Do not include transaction-control statements or operations such as `CREATE INDEX CONCURRENTLY` that require a different execution model.

### Use prepared sources

``MigrationRunner`` accepts ``/SpectroCommon/MigrationSource`` values for SQL directories or immutable prepared definitions. ``MigrationCatalog`` loads and validates their combined history without a database connection. The runner uses the same ledger and lock for both sources.

For Swift authoring, add the optional `SpectroMigrations` product and use its registry and executable entry point. Its guides explain automatic rollback, mixed SQL history, and deployment. Existing `SpectroKit` consumers need no new dependency or protocol changes to update from 2.0 to 2.1.
