# Deploying a migration executable

Build once for the deployment platform and run migrations without a compiler or source checkout.

## Overview

### Build from the application's revision

Keep the migration target in the application package and commit `Package.resolved`. Build both from the same source revision and resolved dependency graph. The installed `spectro` CLI is useful for development; the production artifact is your own migration executable.

```sh
swift build -c release --product MyAppMigrations
swift build -c release --show-bin-path
```

Build on the target platform. A macOS executable is not a Linux artifact. Use the reported binary directory rather than assuming a particular SwiftPM build layout.

### Package the complete artifact

Copy the following into the deployment artifact:

- The `MyAppMigrations` executable.
- All required SwiftPM resource bundles, including bundled SQL history.
- The Swift and system runtime libraries required by that platform and build.

Keep resource bundles beside the executable and preserve their generated names. The deployment process does not need SwiftPM, Mint, the installed `spectro` command, or the source tree.

### Run a deployment step

Supply database settings through the deployment environment, then run:

```sh
/path/to/artifact/MyAppMigrations plan
/path/to/artifact/MyAppMigrations up
```

Provision the database first. Let a nonzero migration exit status fail the deployment. Planning checks registered history offline; it does not report which changes remain pending on the target database. Use `status` when that distinction matters.

### Account for sessions and transactions

Use a direct PostgreSQL connection or session pooling. Migration execution reserves one connection and holds a session advisory lock across the command. Transaction pooling cannot provide the required session continuity.

Each migration and its ledger update run in one transaction. If a later migration fails, earlier successful migrations remain committed; rerunning `up` skips those completed IDs. The default lock wait is 30 seconds. The lower-level ``/Spectro/MigrationRunner`` accepts a custom timeout when embedding the runner.

``MigrationCommand/main(migrations:configuration:)`` handles `SIGINT` and `SIGTERM`, including when the executable is Linux PID 1. Process termination closes its database sockets so PostgreSQL can roll back active work and release the lock. A network partition still depends on PostgreSQL and TCP disconnect detection. In development, the launcher forwards termination to its child process group.

### Keep rollback history available

Retain all applied Swift declarations and SQL resources in later releases. Before rollback, the runner checks the selected applied IDs for missing history or declared irreversibility. A missing ID stops the batch; it does not cause an older change to be rolled back instead.

Test a release artifact from a working directory outside the checkout. This catches missing bundles and accidental dependence on developer tools before deployment. The repository's `scripts/migrations_acceptance.py` exercises copied release artifacts and provides a runtime-only Linux container scenario; the IssueTracker example demonstrates using compiled migrations with an HTTP application.
