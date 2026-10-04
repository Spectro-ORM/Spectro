# Lessons Learned

## Swift 6 Concurrency
- All actors must be Sendable
- SpectroLazyRelation is a value type (struct) — can't use reference semantics
- Type erasure in generics prevents runtime query building

## Testing
- Keep async subprocess waits bounded. A sampled CLI termination test remained inside `Process.waitUntilExit()` after its child was gone; poll `isRunning` with an async deadline before checking termination status.
- Tests use Swift Testing (@Suite, @Test), not XCTest
- Integration tests require live PostgreSQL
- Use TRUNCATE between tests for isolation
- Unique table names prevent test interference

## Architecture
- Query<T> is a value type — every modifier returns a new instance
- SchemaRegistry uses Mirror for field metadata
- Snake_case column mapping is automatic
- QueryCondition init is internal — factory methods using it must live in the Spectro module
- The `where` closure API uses `QueryCondition(sql:parameters:)` with `?` placeholders, not `$N`
- When adding stored closures to value types, use a private full-field initializer to enable copy methods (withLoader, withLoaded) that preserve all fields
- `repo.get(Type.self, id:)` is simpler than a query for belongs-to lookups by PK
- For struct mutating methods, verify no existing callers expect the non-mutating signature before changing

## Macro-Generated Code
- Exercise new property wrappers through the public `@Schema` workflow. Manual test schemas can hide missing generated metadata, row decoding, and JSON encoding; the release review reproduced that gap for `@SoftDelete`.
- withLoader must reset loadState to .notLoaded, not preserve it. The @Schema macro init does `self.posts = []` which sets the relation to `.loaded([])`. If withLoader preserves that state, `load(using:)` short-circuits and returns the stale empty value, never calling the loader. Always reset to .notLoaded when attaching a new loader.
- The @Schema macro generates loader injection in build(from:) for relationships: hasManyLoader for @HasMany, hasOneLoader for @HasOne, belongsToLoader for @BelongsTo. These are auto-attached when entities are built from database rows.
- When generating code for @ID or @ForeignKey properties, always use `prop.typeName` (from `PropertyInfo`) rather than hardcoding "UUID". The `defaultValueExpression(for:)` helper handles mapping type names to default values (UUID() for UUID, 0 for Int, "" for String). Similarly, `as?` casts in loader injection must use the actual PK/FK type from the property declaration.
- In `build(from:)` generation, always use the Swift property name (`prop.name`) as the dictionary key, NOT the column name override. `Schema.from(row:)` populates the dict keyed by property name, not database column name. Mismatching these causes silent data loss.

## Generic Types and Reflection
- When making a property wrapper generic (e.g., `ID` → `ID<T>`), `is ID` pattern matching in Mirror-based code breaks. Use marker protocols (`PrimaryKeyWrapperProtocol`, `ForeignKeyWrapperProtocol`) with `case let v as any ProtocolName:` for runtime type checking.
- `some PrimaryKeyType` (opaque types) cannot be used in static method return types that are closures. Use explicit generic parameters `<PK: PrimaryKeyType>` instead.
- `repo.insert()` always excludes the PK (`excludePrimaryKey: true`). This works for server-generated PKs (UUID defaults, SERIAL) but drops user-supplied String/Int PKs. Use raw parameterized SQL for user-supplied PKs until this is addressed.

## Migrations
- MigrationManager uses epoch seconds (not YYYYMMDDHHMMSS) for timestamps. Files named `<epoch>_<name>.sql`. The CLI generates these with `Int(Date().timeIntervalSince1970)`.
- MigrationManager discovers files relative to CWD at `Sources/Migrations/`. App must be run from the project root.
- The `discoverMigrations()` guard validates `Double(timestamp) < epochNow + 100years`, so YYYYMMDDHHMMSS values (~2e13) silently fail.

## Hummingbird 2.x Integration
- Model files need `import Foundation` for UUID/Date since Spectro doesn't re-export it
- `app.runService()` is the correct entry point (not `app.run()`)
- Always `defer { Task { await spectro.shutdown() } }` for connection pool cleanup
- `ResponseCodable` (from Hummingbird) makes structs JSON-encodable as responses
- Route params: `context.parameters.require("id", as: UUID.self)`

## Error reporting and Swift Testing
- Reproduced SIGBUS by formatting `SpectroError.invalidQuery` without a database: `debugDescription` interpolated `self` recursively. Use a non-recursive description. The full suite and previously disabled transaction tests pass after this fix; do not assume error-reporting crashes are Swift/NIO teardown bugs.
- In a future chain, attach rollback failure handling before throwing the original transaction error. Otherwise a successful rollback is mislabeled as a rollback failure.
- Never let CI ignore a nonzero `swift test` exit status or infer success from partial test output.

## SQL Generation
- PostgreSQL SUM/MIN/MAX on INTEGER returns BIGINT, not DOUBLE — use CAST(... AS DOUBLE PRECISION) for aggregate results
- Always use `.quoted` for identifier quoting — never manual `"\"\(name)\""` interpolation
- SpectroError.invalidSchema requires label: `reason:`
- Guard against empty arrays in SQL generation (e.g., empty `set` in upsert produces invalid SQL)
- Dictionary `.keys` and `.values` iterate in matching order for the same instance, but this is fragile across refactors

## macOS build artifacts
- A passing acceptance run does not guarantee generated bundles remain signable inside cloud-synced Documents. Reproduced codesign rejection from com.apple.FinderInfo on a generated NIO resource bundle; the identical temporary copy signs until that attribute is restored.
- Keep acceptance scratch directories in a persistent local cache outside the synced checkout, and ask SwiftPM for --show-bin-path rather than assuming .build/debug across build engines. Preserve actual build failures and executable overrides.
