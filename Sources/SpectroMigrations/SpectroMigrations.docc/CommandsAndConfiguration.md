# Commands and configuration

Choose a workflow, preview registered SQL, and supply database settings only when needed.

## Overview

### Understand the two entry points

The installed `spectro` command is a development launcher. Your project's compiled executable contains the registered migration history and the runtime commands.

| Development command | Project executable command | Database access |
|---|---|---|
| `spectro migrate plan` | `MyAppMigrations plan` | None |
| `spectro migrate up` | `MyAppMigrations up` | Required |
| `spectro migrate down --step 1` | `MyAppMigrations down --step 1` | Required |
| `spectro migrate status` | `MyAppMigrations status` | Required; read-only |
| `spectro migrate init --target MyAppMigrations` | — | None |
| `spectro generate migration CreateUsers` | — | None in Swift mode |

You can also use `swift run MyAppMigrations <command>` during development. SwiftPM may build or resolve dependencies even for offline commands. In production, run the built binary directly.

### Select Swift mode with a descriptor

`spectro migrate init` creates `.spectro.json` beside your application's `Package.swift`:

```json
{
  "formatVersion": 1,
  "migrations": {
    "product": "MyAppMigrations",
    "sourceDirectory": "Sources/MyAppMigrations"
  }
}
```

Discovery stops at the nearest Swift package. Paths must stay inside that package, including through symlinks. Malformed descriptors and project build failures are errors.

With the descriptor, `up`, `down`, `status`, and `plan` launch the configured product. Generation creates a Swift declaration and prints the registration line. Without a descriptor, `up`, `down`, `status`, and generation use the legacy SQL directory `Sources/Migrations` in the current working directory. Legacy generation also connects to record the pending migration. `plan` requires a Swift target.

### Preview and roll back

```sh
spectro migrate plan
spectro migrate plan --direction down
spectro migrate plan --migration 1791129600_create_users --direction down
```

`plan` previews **all registered migrations**, independently of the database's applied state. The default direction is `up`; up previews use ascending full IDs and down previews use descending IDs. Unknown IDs and irreversible down previews fail before printing a partial plan.

`up` skips completed IDs. `status` reads the ledger without creating it and reports applied IDs missing from the artifact. `down` selects completed IDs in descending order and preflights the entire selected batch for missing or irreversible history.

**Without `--step`, `down` rolls back all completed migrations.** `--step 1` selects the latest; `--step 0` exits without loading database configuration. Negative values are rejected.

### Configure the executable

The default provider reads process environment. Credential options override their corresponding environment values:

| Environment | Option | Default or requirement |
|---|---|---|
| `DB_HOST` | — | `localhost` |
| `DB_PORT` | — | `5432`; integer from 1 through 65535 |
| `DB_USER` | `--username` | Required |
| `DB_PASSWORD` | `--password` | Required; an empty value is accepted |
| `DB_NAME` | `--database` | Required |

Help and planning do not load database configuration. The executable does **not** automatically read `.env`: export settings in your shell or deployment environment. The legacy SQL CLI retains its separate options > `.env` > process environment > defaults precedence.

To share application configuration, pass a lazy provider to ``MigrationCommand``:

```swift
import Spectro
import SpectroMigrations

@main
struct MigrationMain {
    static func main() async {
        await MigrationCommand.main(
            migrations: migrations,
            configuration: { try DatabaseConfiguration.fromEnvironment() }
        )
    }
}
```

The provider returns ``/Spectro/DatabaseConfiguration`` and owns its environment and validation policy. Credential flags override its connection fields while preserving TLS and pool settings. Use the default migration provider for the strict environment validation described in the table.

For embedding or tests, `MigrationCommand.run(arguments:migrations:configuration:)` returns an exit code without exiting the host process. The `main` entry point installs process termination handling; `run` leaves process lifecycle to its caller.

### Find help

```sh
spectro --version
spectro --help
spectro help migrate plan
swift run MyAppMigrations --help
swift run MyAppMigrations down --help
```

`spectro help migrate <command>` shows the launcher's reference without building the application. With a descriptor, `spectro migrate <command> --help` launches the project executable and shows its help, so SwiftPM must be able to build the project.

Database commands return a nonzero status on failure. The launcher preserves the child command's exit status so shell scripts and deployments can stop on errors.
