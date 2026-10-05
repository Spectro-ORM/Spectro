# Migration values and identity

Understand the immutable boundary between an authoring format and the execution engine.

## Overview

### Describe a prepared migration

``PreparedMigration`` contains the full `version` ID, a descriptive `name`, `upSQL`, and a ``MigrationRollback``. The rollback is either explicit SQL or an irreversible reason. Constructing the value does not execute or validate SQL; the catalog validates it before use.

```swift
import SpectroCommon

let prepared = PreparedMigration(
    version: "1791129600_create_labels",
    name: "create_labels",
    upSQL: "CREATE TABLE labels (name TEXT NOT NULL);",
    rollback: .sql("DROP TABLE labels;")
)
let source = MigrationSource.prepared([prepared])
```

Swift migration declarations compile to this representation. ``MigrationSource/sqlDirectory(_:)`` represents an existing SQL directory; ``MigrationSource/prepared(_:)`` supplies in-memory definitions. The execution engine accepts both in one catalog.

### Keep the full ID stable

The full ID includes the timestamp and the name: `1791129600_create_labels`. It is the ledger key, not just a display label. Prepared definitions use an epoch-seconds prefix and lower snake case name. Duplicate full IDs fail across all registered sources. IDs sort lexically, including names when timestamps match.

For existing SQL history, preserve filenames and contents. The full basename without `.sql` remains the ID. Keep applied history in every later artifact so status and rollback can match the database to the shipped definitions.

### Read ledger state

``MigrationFile`` describes a discovered file. ``MigrationRecord`` describes a ledger entry with its full ID, name, timestamp, and ``MigrationStatus``. Status values are `pending`, `completed`, and `failed`; callers should use the status field rather than infer application state from a record's timestamp.

Read-only status does not create a ledger on a fresh database. Migration execution and tracking changes are handled transactionally by the runner in the Spectro module.

### Report planning errors

``MigrationPlanningError`` carries a reason, an optional migration ID, and an optional zero-based operation index. The index points to the operation or SQL statement being validated at the reporting stage. Planning errors describe invalid definitions, duplicate IDs, missing resources, or unsupported rollback structure before execution.

Planning is independent of database connectivity. It checks declaration structure and SQL statement boundaries; PostgreSQL still checks complete SQL syntax, permissions, and existing schema state at execution.
