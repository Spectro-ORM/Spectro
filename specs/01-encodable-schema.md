# Spec: Encodable Conformance for @Schema Types

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** @Schema macro (complete), SchemaMacro extension infrastructure (complete)

---

## 1. Goal

Generate `Encodable` conformance from the `@Schema` macro so that schema types
can be passed directly to `conn.json(encodable:)` or `JSONEncoder` without
manually constructing `[String: String]` dictionaries. This is the single
biggest DX friction point observed in DonutShop, where every route handler
manually maps model fields to string dictionaries.

Today:
```swift
return try conn.json(value: donuts.map { d in
    ["id": "\(d.id)", "name": d.name, "price": "\(d.price)"]
})
```

After:
```swift
return try conn.json(encodable: donuts)
```

---

## 2. Scope

### 2.1 Macro-Generated `Encodable` Conformance

The `@Schema` macro should generate an `Encodable` extension that encodes all
`@Column`, `@ID`, `@Timestamp`, and `@ForeignKey` fields. Relationship fields
(`@HasMany`, `@HasOne`, `@BelongsTo`, `@ManyToMany`) should encode **only when
loaded** (non-nil / non-empty).

Generated output for `Donut`:

```swift
extension Donut: Encodable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case descriptionText = "description_text"
        case price
        case isAvailable = "is_available"
        case categoryId = "category_id"
        case createdAt = "created_at"
        case category
        case toppings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(descriptionText, forKey: .descriptionText)
        try container.encode(price, forKey: .price)
        try container.encode(isAvailable, forKey: .isAvailable)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(createdAt, forKey: .createdAt)
        // Relationships: encode only when loaded
        if let category { try container.encode(category, forKey: .category) }
        if !toppings.isEmpty { try container.encode(toppings, forKey: .toppings) }
    }
}
```

### 2.2 JSON Key Strategy

Column names with `@Column("custom_name")` overrides should use the override
as the JSON key via `CodingKeys`. Fields without overrides use the Swift
property name converted to `snake_case` (matching the database column
convention).

### 2.3 Opt-out Mechanism

Add an `encodable: Bool` parameter to `@Schema` defaulting to `true`:

```swift
@Schema("users")                    // generates Encodable
@Schema("secrets", encodable: false) // skips Encodable generation
```

### 2.4 Relationship Encoding Behavior

| Wrapper | Loaded State | Encoding |
|---------|-------------|----------|
| `@BelongsTo var x: T?` | `nil` (not loaded) | Key omitted |
| `@BelongsTo var x: T?` | `some(value)` | Encoded recursively |
| `@HasMany var xs: [T]` | `[]` (not loaded) | Key omitted |
| `@HasMany var xs: [T]` | `[items]` | Encoded as array |
| `@ManyToMany var xs: [T]` | `[]` (not loaded) | Key omitted |
| `@ManyToMany var xs: [T]` | `[items]` | Encoded as array |

Note: distinguishing "not loaded" from "genuinely empty" requires checking the
`SpectroLazyRelation` state. If the relation is `.notLoaded`, omit the key.
If `.loaded([])`, encode as empty array.

---

## 3. Acceptance Criteria

- [ ] `@Schema("donuts") struct Donut { ... }` automatically conforms to `Encodable`
- [ ] All `@Column`, `@ID`, `@Timestamp`, `@ForeignKey` properties are encoded
- [ ] `@Column("custom_name")` overrides produce the correct JSON key (snake_case)
- [ ] Properties without `@Column` name override use `snake_case` conversion of the Swift name
- [ ] `@BelongsTo` relationships encode when loaded, omit key when `.notLoaded`
- [ ] `@HasMany` / `@ManyToMany` relationships encode when loaded, omit key when `.notLoaded`
- [ ] `@Schema("table", encodable: false)` skips `Encodable` generation
- [ ] Encoding a `Donut` with preloaded `category` includes `"category": {...}` in output
- [ ] Encoding a `Donut` without preloaded `category` omits the `"category"` key entirely
- [ ] `JSONEncoder().encode(donut)` round-trips correctly for all field types (UUID, String, Double, Bool, Date, Int)
- [ ] Compilation succeeds with Swift 6 strict concurrency (`Encodable` conformance is `Sendable`-safe)
- [ ] Existing tests continue to pass (no regressions)
- [ ] New macro expansion tests verify the generated `Encodable` extension for at least 3 schema types

---

## 4. Non-goals

- `Decodable` conformance (schemas are built from `PostgresRow` via `SchemaBuilder`, not JSON).
- Custom `JSONEncoder` date strategies (use ISO 8601 default).
- Controlling which fields are included/excluded per-request (use a DTO for that).
