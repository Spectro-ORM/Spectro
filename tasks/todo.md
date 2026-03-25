# Spectro ORM - Current Sprint

## Schema DSL Improvements — COMPLETE

### Phase 1: Column Name Overrides + FK Binding + Macro Refactor (backward compatible)
- [x] Add `columnName: String?` to `Column<T>` and `ForeignKey` — `@Column("display_name")`
- [x] Add `foreignKey: String?` to `HasMany<T>`, `HasOne<T>`, `BelongsTo<T>` — `@HasMany(foreignKey: "author_id")`
- [x] SchemaMacro: extend PropertyInfo, parse wrapper args, dedup ExtensionMacro, update loader FK injection
- [x] SchemaRegistry: `is` → `let as` pattern matching, add `Column<UUID>` case, use `columnName` override
- [x] Tests: column override, FK override, Column<UUID> (8 new tests)

### Phase 2: Generic Primary Keys (breaking for code using bare `ID` type)
- [x] `PrimaryKeyType` protocol with UUID/Int/String conformances
- [x] `PrimaryKeyWrapperProtocol` + `ForeignKeyWrapperProtocol` marker protocols for reflection
- [x] `ID<T: PrimaryKeyType>` and `ForeignKey<T: PrimaryKeyType>` — generic property wrappers
- [x] Repo + GenericDatabaseRepo + Spectro: `id: UUID` → `id: some PrimaryKeyType`
- [x] SpectroLazyRelation loaders: `parentId: UUID` → generic `PK: PrimaryKeyType`
- [x] PreloadQuery: `extractUUID` → `extractPrimaryKey`/`extractPrimaryKeyData`, `[UUID:]` → `[AnyHashable:]`
- [x] SchemaMacro: type-aware `defaultValueExpression`, type-aware `as?` casts in loaders
- [x] SpectroError.notFound: `id: UUID` → `id: String`
- [x] RelationshipLoader.loadBelongsTo: uses query instead of repo.get for PK-agnostic loading
- [x] Tests: 7 unit + 13 integration for Int/String PKs (20 new tests)

### Review Fixes
- [x] Fixed build(from:) dict key — always use prop.name (not columnName override) to match Schema.from(row:)
- [x] Fixed BelongsTo loader injection to use foreignKeyOverride when present
- [x] Fixed SQL injection in test helper (parameterized query)

## Previous Work — COMPLETE

### Workstreams 1-4
- [x] SpectroLazyRelation.load(using:) with stored loaders
- [x] Dead code cleanup
- [x] Upsert + Bulk Insert
- [x] Aggregate Queries (sum/avg/min/max)
- [x] @Schema macro auto-injects loader closures

### SpectroDemo (Hummingbird Blog API)
- [x] Full REST API validated with curl (CRUD + preloading)

## Future Work
- [x] Support user-supplied primary keys in repo.insert() — `includePrimaryKey: Bool` param on insert/upsert/insertAll
- [x] Fix fromSync(row:) to respect @Column("custom_name") overrides
- [x] Test coverage for .constraint(...) conflict target (4 tests: insert/update/selective set/empty set error)
- [x] Type-safe aggregate API — closure-based `.sum { $0.age }` replaces string-based `.sum("age")`
- [x] Grouped aggregates — GROUP BY/HAVING support with `groupedSum`, `groupedAvg`, `groupedMin`, `groupedMax`, `groupedCount`
