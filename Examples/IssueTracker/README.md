# IssueTracker acceptance application

A small Peregrine 1.2.0 HTTP application consuming this checkout through Spectro's public API. Projects and issues deliberately share IDs, timestamps, and custom `display_name` columns so joined reads exercise the mapping contract.

From the Spectro repository root:

```sh
python3 scripts/acceptance.py
```

Requires macOS 14+, Swift 6.3+ (Peregrine's ESW dependency requires it), Python 3, PostgreSQL client tools (`psql`), and a running PostgreSQL server. Spectro itself still supports Swift 6.0 on Linux. Keep the checkout directory named `Spectro` so SwiftPM's local dependency identity overrides Peregrine's transitive Spectro dependency.

Peregrine 1.2.0 currently blocks this HTTP example on Linux: [its error handler imports Apple's `os` module](https://github.com/Maartz/swift-peregrine/blob/1.2.0/Sources/Peregrine/ErrorRescue.swift#L5). A Swift 6.3.3/Linux build reproduced that failure. CI runs this HTTP acceptance on macOS and Spectro's full PostgreSQL-backed suite on Linux/Swift 6.0. Switch to a verified Peregrine release with portable logging before adding Linux HTTP acceptance.

The default connection is `localhost:5432`, user/password `postgres/postgres`; override `DB_HOST`, `DB_PORT`, `DB_USER`, and `DB_PASSWORD` as needed. Use a local test server whose role can create databases. The command always generates a unique `spectro_acceptance_*` database, ignores any existing `DB_NAME`, and removes its database and HTTP processes on exit.

The acceptance command verifies:

- Project creation with an initial issue in one transaction, using validated changesets.
- Joined IDs, custom names, timestamps, nullable notes, and an absent optional issue over HTTP.
- Validation errors, UUID casting, and rollback when creating the initial issue fails.
- Two competing requests for the same unique slug: one HTTP 201, one HTTP 409, one persisted project and issue.
- A migration that adds and backfills issue priority after records already exist.
- Server restart, migration rollback/reapply, and preservation of all HTTP-visible data.

`--skip-build` reuses built executables. `SPECTRO_CLI_PATH` and `SPECTRO_EXAMPLE_PATH` can override their paths for a custom SwiftPM scratch directory. Acceptance database assertions use `psql` independently of the ORM.

Routes are `GET /health`, `GET /projects`, `POST /projects`, and `POST /issues`. This is a local correctness fixture: its intentional transaction-failure response includes the formatted error so acceptance exercises that path. Deploying an application requires its own authentication and public error policy.
