# Changelog

## 2.0.0 — 2026-10-04

Spectro 2.0 focuses on PostgreSQL correctness and application-level validation. It also includes the changeset, pagination, and soft-delete APIs added since 1.2.0.

### Breaking changes

- Custom `Repo` conformers must implement `insert(_ changeset:)` and `update(_ changeset:)`. Spectro's built-in repositories already implement both requirements, including inside transactions.
- Model-returning right joins now throw because their result types cannot represent an absent main model. Reverse the query and use a left join. Typed self joins and repeated tables are rejected until table aliases are supported; typed left joins require a nonnullable primary key on the joined schema.
- Typed joined reads now throw when a present row cannot be decoded, instead of substituting default values or silently omitting it.
- Migration runners require a direct or session-pooled connection and transaction-compatible SQL. Use the 2.0 runner consistently when multiple processes can migrate the same database.

See the [upgrade guide](docs/UPGRADING-2.0.md) for migration examples and operational changes.

### Added

- Changesets with permitted-field casting, validators, serializable errors, uniqueness checks, and repository insert/update support.
- `Query.page(size:page:)` with total counts and navigation metadata.
- Opt-in soft deletes with `@SoftDelete` and `.withDeleted()`.
- A public-API IssueTracker HTTP application and repeatable acceptance command covering transactions, joined reads, competing writes, populated migrations, rollback/reapply, and restart persistence.

### Fixed

- `@Schema` recognizes `@SoftDelete`, generates filtering metadata, and preserves deletion timestamps in decoded models and JSON.
- Migration SQL and status recording now use the same transaction. Competing migration commands serialize through a PostgreSQL advisory lock, with bounded lock waiting and cancellation cleanup.
- Joined models decode from separate projections, preserving IDs, timestamps, custom column mappings, and nullable fields without column collisions. An unmatched left-joined model is `nil`.
- Query parameters follow SQL order across joins, filters, and HAVING clauses; soft-delete filters are qualified in joined queries.
- Changeset casting rejects invalid field types and non-finite numbers before persistence. Both repositories honor custom column names.
- Recursive error formatting no longer crashes when reporting `SpectroError`; transaction failures preserve the original error after successful rollback.
- Database connections honor configured TLS settings and reject invalid settings before allocating event-loop threads.
- Fresh-database migration commands initialize their tracking state, while migration status remains read-only.
- CI propagates test failures. Acceptance build artifacts use a local cache to avoid macOS signing failures caused by Finder metadata in cloud-synced folders.

### Compatibility and validation

- Spectro requires Swift 6.0+ and supports macOS 13+ and Linux with PostgreSQL.
- The core suite contains 368 tests, including concurrent migration processes, cancellation, and macro-defined soft deletes. CI runs PostgreSQL-backed tests on macOS and Linux.
- The IssueTracker acceptance application requires macOS 14+, Swift 6.3+, and an Xcode 26.3+ SDK. Its pinned Peregrine 1.2.0 dependency currently prevents that example from building on Linux; Spectro's core Linux support is unaffected.

[Full comparison with 1.2.0](https://github.com/Spectro-ORM/Spectro/compare/1.2.0...2.0.0)
