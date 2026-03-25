# Spectro

A Swift ORM for PostgreSQL, inspired by Elixir's Ecto. Property-wrapper schemas, a composable query builder, actor-based concurrency, and a CLI for migrations.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Schema Definition](#schema-definition)
- [CRUD Operations](#crud-operations)
- [Query Builder](#query-builder)
- [Relationships](#relationships)
- [Transactions](#transactions)
- [Aggregates and GROUP BY](#aggregates-and-group-by)
- [Field Selection](#field-selection)
- [CLI Reference](#cli-reference)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Development](#development)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- **Property-wrapper schema definitions** -- `@ID`, `@Column`, `@Timestamp`, `@ForeignKey`, `@HasMany`, `@HasOne`, `@BelongsTo`, `@ManyToMany`
- **`@Schema` macro** -- generates `SchemaBuilder` conformance at compile time (zero boilerplate)
- **Generic primary keys** -- `@ID<UUID>`, `@ID<Int>`, `@ID<String>` via the `PrimaryKeyType` protocol
- **Immutable query builder** -- `Query<T>` is a value type; every `.where()`, `.join()`, `.orderBy()` returns a new query
- **Type-safe aggregates** -- `.sum()`, `.avg()`, `.min()`, `.max()`, `.count()` with `GROUP BY` and `HAVING` support
- **Upsert and bulk insert** -- `ON CONFLICT` upserts and multi-row inserts with automatic batching
- **Relationship preloading** -- batch-loads `HasMany`, `HasOne`, `BelongsTo`, and `ManyToMany` relationships to prevent N+1 queries
- **Transaction support** -- `READ COMMITTED` isolation with automatic rollback; full CRUD and query builder available inside transactions via `QueryExecutor`
- **Actor-based connection pooling** -- built on SwiftNIO and PostgresKit
- **Plain SQL migrations** -- timestamped `.sql` files with `-- migrate:up` / `-- migrate:down` markers
- **CLI tool** -- `spectro` binary for database creation, migrations, and status
- **Swift 6 strict concurrency** -- full `Sendable` compliance across all types

## Requirements

- Swift 6.0+ (managed via `mise.toml`)
- macOS 13+
- PostgreSQL

## Installation

### As a Swift Package dependency

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/Maartz/Spectro.git", from: "1.0.0")
```

Then add `"SpectroKit"` to your target's dependencies:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SpectroKit", package: "Spectro"),
    ]
)
```

### CLI via Mint

The `spectro` CLI is distributed via [Mint](https://github.com/yonaskolb/Mint):

```bash
mint install Maartz/Spectro
```

Pin a version in your `Mintfile`:

```
Maartz/Spectro@1.0.0
```

## Quick Start

### 1. Define a schema

```swift
import Spectro

@Schema("users")
struct User {
    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Timestamp var createdAt: Date
}
```

The `@Schema` macro generates `Schema` and `SchemaBuilder` conformance at compile time -- no manual `init()` or `build(from:)` required.

### 2. Connect and query

```swift
let spectro = try Spectro(
    hostname: "localhost",
    username: "postgres",
    password: "postgres",
    database: "myapp_dev"
)

// Insert
let user = try await spectro.insert(User())

// Query
let repo = spectro.repository()
let activeUsers = try await repo.query(User.self)
    .where { $0.name == "John" }
    .orderBy({ $0.createdAt }, .desc)
    .limit(10)
    .all()

// Get by ID
let found = try await spectro.get(User.self, id: someUUID)

// Update
let updated = try await spectro.update(User.self, id: someUUID, changes: ["name": "Jane"])

// Delete
try await spectro.delete(User.self, id: someUUID)

// Shutdown (always call before releasing)
await spectro.shutdown()
```

## Schema Definition

### The @Schema macro

The `@Schema("table_name")` macro generates everything needed to map a struct to a database table:

- `static let tableName` from the string argument
- A default `init()` with type-appropriate defaults
- A convenience `init(column params...)` for `@Column` and `@ForeignKey` properties
- `SchemaBuilder.build(from:)` for row mapping

```swift
@Schema("users")
struct User {
    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Column var bio: String?
    @Timestamp var createdAt: Date
}
```

### Property wrappers

| Wrapper | Purpose | Example |
|---------|---------|---------|
| `@ID<T>` | Primary key (UUID, Int, or String) | `@ID var id: UUID` |
| `@Column<T>` | Regular column, optional name override | `@Column("display_name") var name: String` |
| `@Timestamp` | Date column | `@Timestamp var createdAt: Date` |
| `@ForeignKey<T>` | Foreign key reference, optional name override | `@ForeignKey var userId: UUID` |
| `@HasMany<T>` | One-to-many relationship, optional FK binding | `@HasMany(foreignKey: "authorId") var posts: [Post]` |
| `@HasOne<T>` | One-to-one relationship | `@HasOne var profile: Profile?` |
| `@BelongsTo<T>` | Inverse of HasMany/HasOne | `@BelongsTo var user: User?` |
| `@ManyToMany<T>` | Many-to-many via junction table | `@ManyToMany(junctionTable: "user_tags") var tags: [Tag]` |

### Generic primary keys

Primary keys are not limited to UUID. Any type conforming to `PrimaryKeyType` can be used. Built-in conformances: `UUID`, `Int`, `String`.

```swift
@Schema("articles")
struct Article {
    @ID var id: Int          // SERIAL primary key
    @Column var title: String
}

@Schema("slugs")
struct Slug {
    @ID var id: String       // TEXT primary key
    @Column var target: String
}
```

Foreign keys match the primary key type of the referenced table:

```swift
@Schema("comments")
struct Comment {
    @ID var id: UUID
    @Column var body: String
    @ForeignKey var articleId: Int    // references Article's Int PK
}
```

### Column name overrides

By default, Swift property names are converted to `snake_case` for column names. Override with a string argument:

```swift
@Schema("users")
struct User {
    @ID var id: UUID
    @Column("display_name") var name: String       // maps to "display_name" column
    @ForeignKey("team_ref_id") var teamId: UUID     // maps to "team_ref_id" column
}
```

### Manual schema definition

If you prefer not to use the macro, implement `Schema` and `SchemaBuilder` manually:

```swift
struct User: Schema, SchemaBuilder {
    static let tableName = "users"

    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Timestamp var createdAt: Date

    init() {
        self.id = UUID()
        self.name = ""
        self.email = ""
        self.createdAt = Date()
    }

    static func build(from values: [String: Any]) -> User {
        var user = User()
        if let v = values["id"] as? UUID { user.id = v }
        if let v = values["name"] as? String { user.name = v }
        if let v = values["email"] as? String { user.email = v }
        if let v = values["createdAt"] as? Date { user.createdAt = v }
        return user
    }
}
```

## CRUD Operations

All CRUD is available on both the `Spectro` facade and the `GenericDatabaseRepo` actor (via `spectro.repository()`).

```swift
let repo = spectro.repository()

// Insert a single record
let user = try await repo.insert(User(name: "Alice", email: "alice@example.com"))

// Insert with explicit primary key (e.g. for seeding)
let admin = try await repo.insert(
    User(id: knownUUID, name: "Admin", email: "admin@example.com"),
    includePrimaryKey: true
)

// Get by primary key
let found = try await repo.get(User.self, id: someUUID)

// Get or throw SpectroError.notFound
let mustExist = try await repo.getOrFail(User.self, id: someUUID)

// Fetch all
let everyone = try await repo.all(User.self)

// Update by ID
let updated = try await repo.update(User.self, id: someUUID, changes: [
    "name": "Bob",
    "email": "bob@example.com"
])

// Delete by ID
try await repo.delete(User.self, id: someUUID)
```

### Upsert

Insert or update on conflict using `ConflictTarget`:

```swift
// Upsert on column conflict -- updates all non-PK columns
let user = try await repo.upsert(
    User(name: "Alice", email: "alice@example.com"),
    conflictTarget: .columns(["email"])
)

// Upsert with specific columns to update
let user = try await repo.upsert(
    User(name: "Alice", email: "alice@example.com"),
    conflictTarget: .columns(["email"]),
    set: ["name"]    // only update name on conflict
)

// Upsert on named constraint
let user = try await repo.upsert(
    User(name: "Alice", email: "alice@example.com"),
    conflictTarget: .constraint("users_email_unique")
)
```

### Bulk insert

Insert multiple records in a single query. Automatically batches at 1000 rows to stay under PostgreSQL's parameter limit:

```swift
let users = [
    User(name: "Alice", email: "alice@example.com"),
    User(name: "Bob", email: "bob@example.com"),
    User(name: "Carol", email: "carol@example.com"),
]
let inserted = try await repo.insertAll(users)
```

## Query Builder

`Query<T>` is an immutable value type. Every method returns a new query, so you can safely branch and reuse intermediate queries.

```swift
let repo = spectro.repository()

let base = repo.query(User.self)
    .where { $0.isActive == true }

// Branch 1: recent users
let recent = try await base
    .orderBy({ $0.createdAt }, .desc)
    .limit(10)
    .all()

// Branch 2: count
let total = try await base.count()
```

### Where clauses

```swift
// Equality
.where { $0.name == "John" }
.where { $0.status != "banned" }

// Comparison
.where { $0.age >= 18 }
.where { $0.score < 100 }

// String patterns (case-sensitive)
.where { $0.name.like("J%") }
.where { $0.name.contains("ohn") }          // LIKE '%ohn%'
.where { $0.email.endsWith("@gmail.com") }  // LIKE '%@gmail.com'
.where { $0.name.startsWith("J") }          // LIKE 'J%'

// String patterns (case-insensitive)
.where { $0.name.ilike("%john%") }
.where { $0.name.iContains("john") }        // ILIKE '%john%'
.where { $0.name.iStartsWith("j") }         // ILIKE 'j%'
.where { $0.name.iEndsWith("son") }         // ILIKE '%son'

// Collection
.where { $0.status.in(["active", "pending"]) }
.where { $0.role.notIn(["banned", "suspended"]) }
.where { $0.age.between(18, and: 65) }

// Null checks
.where { $0.deletedAt.isNull() }
.where { $0.email.isNotNull() }

// Date
.where { $0.createdAt.isToday() }
.where { $0.createdAt.isThisWeek() }
.where { $0.createdAt.isThisMonth() }
.where { $0.createdAt.isThisYear() }
.where { $0.createdAt.before(cutoffDate) }
.where { $0.createdAt.after(startDate) }

// Logical operators
.where { $0.role == "admin" || $0.role == "moderator" }
.where { ($0.age >= 18) && ($0.isActive == true) }
.where { !($0.status == "banned") }
```

### Ordering

```swift
// Single field (ascending by default)
.orderBy { $0.createdAt }

// Explicit direction
.orderBy({ $0.createdAt }, .desc)

// Multiple fields
.orderBy({ $0.name }, .asc, then: { $0.createdAt }, .desc)
```

### Pagination

```swift
.limit(20)
.offset(40)
```

### Joins

```swift
// Inner join
let results = try await repo.query(User.self)
    .join(Post.self, on: { $0.left.id == $0.right.userId })
    .where { $0.name == "John" }
    .all()

// Left join
let results = try await repo.query(User.self)
    .leftJoin(Post.self, on: { $0.left.id == $0.right.userId })
    .all()

// Right join
let results = try await repo.query(User.self)
    .rightJoin(Post.self, on: { $0.left.id == $0.right.userId })
    .all()

// Through join (many-to-many via junction table)
let results = try await repo.query(User.self)
    .joinThrough(Tag.self, through: UserTag.self, on: { builder in
        (builder.main.id == builder.junction.userId,
         builder.junction.tagId == builder.target.id)
    })
    .all()
```

### Terminal methods

| Method | Returns | Description |
|--------|---------|-------------|
| `.all()` | `[T]` | Execute query, return all matching rows |
| `.first()` | `T?` | Execute query, return first row or nil |
| `.firstOrFail()` | `T` | Execute query, throw `SpectroError.notFound` if empty |
| `.count()` | `Int` | Return count of matching rows |

## Relationships

### Defining relationships

```swift
@Schema("users")
struct User {
    @ID var id: UUID
    @Column var name: String
    @HasMany var posts: [Post]
    @HasOne var profile: Profile?
    @ManyToMany(junctionTable: "user_tags", parentFK: "userId", relatedFK: "tagId")
    var tags: [Tag]
}

@Schema("posts")
struct Post {
    @ID var id: UUID
    @Column var title: String
    @ForeignKey var userId: UUID
    @BelongsTo var user: User?
}

@Schema("profiles")
struct Profile {
    @ID var id: UUID
    @Column var bio: String
    @ForeignKey var userId: UUID
}

@Schema("tags")
struct Tag {
    @ID var id: UUID
    @Column var name: String
}

@Schema("user_tags")
struct UserTag {
    @ID var id: UUID
    @ForeignKey var userId: UUID
    @ForeignKey var tagId: UUID
}
```

### Preloading (N+1 prevention)

Preloading executes one additional query per relationship (not one per row):

```swift
// Load users with their posts (2 queries total)
let users = try await repo.query(User.self)
    .preload(\.$posts)
    .all()

// Chain multiple preloads
let users = try await repo.query(User.self)
    .preload(\.$posts)
    .preload(\.$profile)
    .preload(\.$tags)        // many-to-many preload
    .all()

// Override foreign key when it doesn't follow convention
let posts = try await repo.query(Post.self)
    .preload(\.$author, foreignKey: "authorId")
    .all()
```

Preload queries support chaining with `.where()`, `.orderBy()`, and `.limit()`:

```swift
let users = try await repo.query(User.self)
    .where { $0.isActive == true }
    .preload(\.$posts)
    .orderBy({ $0.name }, .asc)
    .limit(50)
    .all()
```

## Transactions

Transactions use `READ COMMITTED` isolation with automatic rollback on error. The closure receives a `Repo`-conforming object with full CRUD and query builder support:

```swift
let (user, profile) = try await spectro.transaction { repo in
    let user = try await repo.insert(User(name: "Alice", email: "alice@example.com"))
    let profile = try await repo.insert(Profile(bio: "Hello!", userId: user.id))

    // Query builder works inside transactions
    let count = try await repo.query(User.self)
        .where { $0.isActive == true }
        .count()

    return (user, profile)
}
```

Both `GenericDatabaseRepo` and `TransactionRepo` conform to the `Repo` protocol, so code that accepts `any Repo` works transparently inside and outside transactions. The `QueryExecutor` protocol allows `Query<T>` to execute against both pooled connections and pinned transaction connections.

Nested transactions are not supported and will throw `SpectroError.transactionAlreadyStarted`.

## Aggregates and GROUP BY

### Simple aggregates

```swift
let total = try await repo.query(Order.self)
    .where { $0.status == "completed" }
    .sum { $0.amount }         // Double?

let average = try await repo.query(Order.self)
    .avg { $0.amount }         // Double?

let highest = try await repo.query(Order.self)
    .max { $0.amount }         // Double?

let lowest = try await repo.query(Order.self)
    .min { $0.amount }         // Double?

let count = try await repo.query(Order.self)
    .where { $0.status == "completed" }
    .count()                   // Int
```

### Grouped aggregates

Combine `.groupBy()` with grouped aggregate methods to get per-group results:

```swift
// Sum of order amounts grouped by status
let results = try await repo.query(Order.self)
    .groupBy { $0.status }
    .groupedSum { $0.amount }
// returns [GroupedResult] where each has .group["status"] and .value

// Group by multiple fields
let results = try await repo.query(Order.self)
    .groupBy({ $0.status }, { $0.region })
    .groupedCount()

// HAVING clause
let results = try await repo.query(Order.self)
    .groupBy { $0.status }
    .having { $0.amount > 100 }
    .groupedSum { $0.amount }
```

Available grouped methods: `groupedSum`, `groupedAvg`, `groupedMin`, `groupedMax`, `groupedCount`.

Each returns `[GroupedResult]`:

```swift
public struct GroupedResult: Sendable {
    public let group: [String: String]   // GROUP BY column values
    public let value: Double?            // aggregate result
}
```

## Field Selection

Select specific columns instead of `SELECT *` using `TupleQuery`:

```swift
// Single field
let names: [String] = try await repo.query(User.self)
    .select { $0.name }
    .all()

// Two fields
let pairs: [Tuple2<String, String>] = try await repo.query(User.self)
    .select { ($0.name, $0.email) }
    .all()
// Access: pairs[0]._0 (name), pairs[0]._1 (email)

// Three fields
let triples: [Tuple3<String, String, Int>] = try await repo.query(User.self)
    .select { ($0.name, $0.email, $0.age) }
    .all()

// Four fields
let quads: [Tuple4<UUID, String, String, Bool>] = try await repo.query(User.self)
    .select { ($0.id, $0.name, $0.email, $0.isActive) }
    .all()
```

`TupleQuery` supports `.where()`, `.orderBy()`, `.limit()`, `.offset()`, `.first()`, `.firstOrFail()`, and `.count()`.

## CLI Reference

```
spectro database create    Create a new PostgreSQL database
spectro database drop      Drop an existing database
spectro migrate up         Run all pending migrations
spectro migrate down       Rollback applied migrations (--step N)
spectro migrate status     Show migration status
spectro generate migration <name>   Generate a new SQL migration file
```

All commands accept `--username`, `--password`, and `--database` flags. Values are resolved in order: CLI flags > `.env` file > environment variables > defaults.

### Migration files

Migrations are plain SQL in `Sources/Migrations/`, named `YYYYMMDDHHMMSS_<name>.sql`:

```sql
-- migrate:up
CREATE TABLE "users" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL DEFAULT '',
    "email" TEXT NOT NULL DEFAULT '',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- migrate:down
DROP TABLE "users";
```

The `SQLStatementParser` handles semicolons inside dollar-quoted strings, inline `--` comments, and `/* */` block comments.

### Generate a migration

```bash
spectro generate migration CreateUsers
# Creates: Sources/Migrations/20260324120000_CreateUsers.sql
```

### Run migrations

```bash
# Apply all pending
spectro migrate up

# Rollback last migration
spectro migrate down

# Rollback N migrations
spectro migrate down --step 3

# Check status
spectro migrate status
```

## Architecture

Spectro is organized into four targets:

| Target | Product | Role |
|---|---|---|
| `SpectroCommon` | `SpectroCommon` | Shared types (zero external deps): `Inflector`, `MigrationFile`, `MigrationRecord`, error enums, `String.snakeCase()` |
| `SpectroMacros` | Compiler plugin | `@Schema` macro implementation via SwiftSyntax |
| `Spectro` | `SpectroKit` | Core ORM library: schemas, query builder, connection pool, migrations |
| `SpectroCLI` | `spectro` | CLI executable (ArgumentParser-based) |

### Core actors

- **`DatabaseConnection`** -- wraps an NIO `EventLoopGroupConnectionPool<PostgresConnectionSource>`; bridges futures to async/await via `withCheckedThrowingContinuation`; tracks in-flight operations for safe shutdown
- **`GenericDatabaseRepo`** -- implements the `Repo` protocol; primary CRUD layer with query building, raw SQL, and transaction support
- **`SchemaRegistry`** -- singleton actor; inspects schema types via `Mirror`; caches field metadata for row mapping

### Key protocols

- **`Schema`** -- requires `tableName: String` and `init()`
- **`SchemaBuilder`** -- adds `static func build(from: [String: Any]) -> Self` for reflection-free row mapping
- **`PrimaryKeyType`** -- `UUID`, `Int`, `String` conformances; provides `toPostgresData()`, `fromPostgresData()`, `defaultValue`, `fieldType`
- **`Repo`** -- common interface for `GenericDatabaseRepo` and `TransactionRepo`; defines `get`, `insert`, `update`, `delete`, `upsert`, `insertAll`, `transaction`, `query`
- **`QueryExecutor`** -- abstraction over query execution so `Query<T>` works with both pooled connections and pinned transaction connections

### Query builder internals

`Query<T>` stores conditions with `?` as positional sentinels. Placeholder numbering (`$1`, `$2`, ...) is applied in a single left-to-right pass at SQL assembly time via `renumberPlaceholders()`. This means individual operators never need to know their absolute parameter index.

### Data flow

```
Spectro (facade)
  └─ GenericDatabaseRepo (actor, Repo protocol)
       └─ DatabaseConnection (actor, QueryExecutor protocol)
            └─ EventLoopGroupConnectionPool<PostgresConnectionSource>
                 └─ PostgresConnection (NIO EventLoop)

Query<T> ──execute──▶ QueryExecutor.executeQuery()
                        ├─ DatabaseConnection (pooled)
                        └─ TransactionContext (pinned connection)
```

See [docs/architecture.html](docs/architecture.html) for the full architecture reference with diagrams.

## Configuration

### Environment variables

```
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=myapp_dev
```

### .env file

Create a `.env` file in your project root. The CLI reads it automatically:

```
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=myapp_dev
```

### Programmatic configuration

```swift
// From explicit parameters
let spectro = try Spectro(
    hostname: "localhost",
    port: 5432,
    username: "postgres",
    password: "postgres",
    database: "myapp_dev",
    maxConnectionsPerEventLoop: 4
)

// From environment variables (DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME)
let spectro = try Spectro.fromEnvironment()

// From a DatabaseConfiguration struct (supports TLS)
let config = DatabaseConfiguration(
    hostname: "db.example.com",
    port: 5432,
    username: "app",
    password: "secret",
    database: "production",
    maxConnectionsPerEventLoop: 8,
    numberOfThreads: System.coreCount,
    tlsConfiguration: nil
)
let spectro = try Spectro(configuration: config)
```

## Development

### Prerequisites

- Swift 6.0+ (install via [mise](https://mise.jdx.dev/), `brew install swift`, or [swiftly](https://swift-server.github.io/swiftly/))
- PostgreSQL (local install or Docker)

### Build

```bash
# Debug build
swift build

# Release build
swift build -c release

# CLI only
swift build --product spectro

# Run CLI from source
./.build/debug/spectro migrate status
```

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [postgres-kit](https://github.com/vapor/postgres-kit) | 2.7+ | PostgreSQL driver and connection pooling |
| [sql-kit](https://github.com/vapor/sql-kit) | 3.30+ | SQL building utilities |
| [async-kit](https://github.com/vapor/async-kit) | 1.15+ | Connection pool infrastructure |
| [swift-nio](https://github.com/apple/swift-nio) | 2.34+ | Async I/O runtime |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.2+ | CLI argument parsing |
| [swift-syntax](https://github.com/apple/swift-syntax) | 600+ | `@Schema` macro implementation |

## Testing

Tests use [Swift Testing](https://developer.apple.com/documentation/testing/) (`@Suite`, `@Test`), not XCTest.

### Setup

Integration tests require a live PostgreSQL database:

```bash
# Set environment variables (or use defaults)
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=postgres
export DB_PASSWORD=postgres
export TEST_DB_NAME=spectro_test

# Create the test database (one-time)
./Tests/setup_test_db.sh
```

### Run tests

```bash
# All tests
swift test

# Specific suite
swift test --filter CoreFunctionalTests

# Query tests only
swift test --filter QueryTests

# Aggregate tests
swift test --filter AggregateQueryTests
```

### Test structure

```
Tests/SpectroTests/
├── Helpers/
│   ├── TestDatabase.swift        # Test DB connection setup
│   └── TestSchemas.swift         # Schema definitions for tests
├── SchemaTests/
│   ├── SchemaTests.swift         # Schema registration and metadata
│   ├── RelationshipTests.swift   # Relationship property wrappers
│   ├── LazyLoaderTests.swift     # SpectroLazyRelation state machine
│   └── MacroLoaderInjectionTests.swift
├── QueryTests/
│   ├── QueryTests.swift          # SQL generation for Query<T>
│   ├── QueryOperatorTests.swift  # All operator combinations
│   ├── QueryExecutionTests.swift # Live query execution
│   ├── PreloadTests.swift        # Relationship preloading
│   └── AggregateQueryTests.swift # SUM, AVG, MIN, MAX, GROUP BY
├── RepoTests/
│   ├── RepositoryTests.swift     # CRUD operations
│   ├── NonUUIDPrimaryKeyTests.swift # Int and String PK support
│   ├── UpsertBulkInsertTests.swift  # Upsert and insertAll
│   └── TransactionTests.swift    # Transaction isolation and rollback
└── MigrationTests/
    ├── SQLStatementParserTests.swift
    └── StringCase.swift          # snake_case conversion
```

## Troubleshooting

### Connection refused

```
SpectroError.connectionFailed: Database connection failed
```

1. Verify PostgreSQL is running: `pg_isready` or `docker ps`
2. Check env vars: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
3. Verify the database exists: `psql -l | grep myapp_dev`

### Insert did not return a row

```
SpectroError.databaseError: Insert did not return a row
```

The table likely does not exist. Run migrations first:

```bash
spectro migrate up
```

### Schema must implement SchemaBuilder

```
SpectroError.invalidSchema: Schema User must implement SchemaBuilder
```

Either use the `@Schema` macro or manually conform to `SchemaBuilder`:

```swift
// Option A: use the macro
@Schema("users")
struct User { ... }

// Option B: manual conformance
struct User: Schema, SchemaBuilder {
    static func build(from values: [String: Any]) -> User { ... }
}
```

### Transaction already started

```
SpectroError.transactionAlreadyStarted
```

Nested transactions are not supported. Restructure your code so that all work happens within a single `transaction` closure.

### Shutdown crashes (SIGBUS)

Always call `await spectro.shutdown()` before releasing the `Spectro` instance. The connection pool tracks in-flight operations and waits for them to complete before tearing down.

## License

MIT
