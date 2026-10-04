# Upgrading to Spectro 2.0

Update your Swift package dependency to `from: "2.0.0"` and any Mint pin to `Spectro-ORM/Spectro@2.0.0`. The package products remain `SpectroKit`, `SpectroCommon`, and `spectro`; library code continues to use `import Spectro`.

## Custom repository implementations

`Repo` now requires these changeset overloads:

```swift
func insert<T: Schema>(_ changeset: Changeset<T>) async throws -> T
func update<T: Schema>(_ changeset: Changeset<T>) async throws -> T
```

Applications using `GenericDatabaseRepo` or the repository supplied to a transaction already have these implementations. Add both methods to custom repositories and test doubles. Wrappers can forward them to their underlying repository; transaction wrappers must forward to the current transaction's repository so writes stay in that transaction.

Implementations should validate the changeset before writing, persist the supplied changes using the schema's column mappings, and return the stored model. Updates require existing `changeset.data`; an unchanged valid update returns that existing model. The built-in repositories reject inserts with no changes.

## Joined reads

Typed joins use disjoint projections for each model. Matching models retain their own IDs, custom column names, dates, and nullable values. A missing left-joined row is `nil`; invalid data in a present row throws a decoding error.

Model-returning right joins are rejected: `[T]` and `[(T, U?)]` cannot represent the absent main model that a right join permits. To preserve every post, query posts and left-join users:

```swift
let postsWithUsers: [(Post, User?)] = try await repo.query(Post.self)
    .leftJoinAndExecute(User.self, on: { $0.left.userId == $0.right.id })
```

Typed joins also reject self joins and repeated table names because table aliases are not yet supported. A typed left join requires a mapped, nonnullable primary key on the joined schema to distinguish an unmatched row from a matching row containing nullable fields.

## Migration execution

Use the 2.0 CLI or migration manager for every process that can run migrations against a database. Older runners do not participate in the new advisory-lock protocol, so avoid overlapping old and new runners during rollout.

Use a direct PostgreSQL connection or a session-pooling proxy for migrations. Transaction-pooling proxies do not preserve the session ownership required by the advisory lock; see [PgBouncer's compatibility table](https://www.pgbouncer.org/features.html). Application traffic can use its own connection configuration.

Migration commands acquire a database-scoped advisory lock before bootstrap and discovery. Each migration's SQL and tracking changes then run in one transaction. The default lock wait is 30 seconds; library callers can configure it:

```swift
let migrations = spectro.migrationManager(lockTimeout: .seconds(60))
try await migrations.runMigrations()
```

The timeout covers advisory-lock waiting, separately from pool acquisition and SQL execution. Handle `MigrationError.lockTimeout` as a competing migration runner, rather than as a completed deployment. Cancellation closes the command's reserved session and releases its pool slot.

Existing SQL migration files and tracking tables keep their format. `migrate status` remains read-only, including on a fresh database. Negative rollback step counts are rejected.

Review pending SQL files for transaction compatibility. Statements such as `CREATE INDEX CONCURRENTLY`, which [PostgreSQL prohibits inside a transaction](https://www.postgresql.org/docs/16/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY), cannot run through this migration manager. Run such operations separately through an appropriate deployment procedure; do not add `BEGIN`, `COMMIT`, or `ROLLBACK` to migration files to bypass the manager's transaction.

## Input casting and TLS

Use `Changeset.cast` for external parameters, with Swift property names in `permitted`. Invalid types and non-finite numbers produce validation errors; numeric, boolean, UUID, and ISO 8601 date strings are converted when supported by the schema. Direct changeset initialization and `putChange` accept trusted application values without casting.

`DatabaseConfiguration.tlsConfiguration` is now honored. Applications that supplied TLS settings while relying on the previous behavior must use settings that match their PostgreSQL endpoint and trust configuration.

## Platform requirements

The library and CLI support Swift 6.0+ on macOS 13+ and Linux. The optional [IssueTracker acceptance application](../Examples/IssueTracker/README.md) requires macOS 14+ and Swift 6.3+ because of its pinned Peregrine dependencies.
