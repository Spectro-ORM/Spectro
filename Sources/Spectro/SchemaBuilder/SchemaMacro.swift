/// Generates a complete `Schema` + `SchemaBuilder` + `Encodable` conformance for a struct.
///
/// Annotate your struct with `@Schema("table_name")` and the macro generates:
/// - `static let tableName` — from the string argument
/// - `init()` — default initializer with type-appropriate defaults
/// - `init(column params...)` — convenience initializer for `@Column`/`@ForeignKey` properties
/// - `SchemaBuilder.build(from:)` — row-mapping from `[String: Any]`
/// - `Encodable` conformance — `CodingKeys` enum and `encode(to:)` method
///
/// The struct automatically conforms to `Schema`, `SchemaBuilder`, and `Encodable` —
/// no manual protocol conformance needed.
///
/// ## Encodable Behavior
///
/// - All `@Column`, `@ID`, `@Timestamp`, `@ForeignKey` properties are encoded
/// - JSON keys use `snake_case` conversion of the Swift property name
/// - `@Column("custom_name")` overrides produce the custom name as the JSON key
/// - Relationship properties (`@HasMany`, `@HasOne`, `@BelongsTo`, `@ManyToMany`)
///   encode only when loaded; the key is omitted when the relation is `.notLoaded`
///
/// To opt out of `Encodable` generation:
/// ```swift
/// @Schema("secrets", encodable: false)
/// ```
///
/// ## Usage
///
/// ```swift
/// @Schema("users")
/// struct User {
///     @ID var id: UUID
///     @Column var name: String
///     @Column var email: String
///     @Column var bio: String?
///     @Timestamp var createdAt: Date
/// }
/// ```
///
/// Relationship wrappers (`@HasMany`, `@HasOne`, `@BelongsTo`) are handled in
/// `init()` with sensible defaults but are not included as parameters in the
/// convenience initializer, nor in `build(from:)`.
///
/// If you provide your own `tableName` or `init()` in the struct body, the macro
/// skips generating those members.
@attached(member, names: named(tableName), named(init), named(_keyPathToColumn))
@attached(extension, conformances: Schema, SchemaBuilder, Encodable, names: named(build), named(CodingKeys), named(encode))
public macro Schema(_ tableName: String) = #externalMacro(module: "SpectroMacros", type: "SchemaMacro")

@attached(member, names: named(tableName), named(init), named(_keyPathToColumn))
@attached(extension, conformances: Schema, SchemaBuilder, Encodable, names: named(build), named(CodingKeys), named(encode))
public macro Schema(_ tableName: String, encodable: Bool) = #externalMacro(module: "SpectroMacros", type: "SchemaMacro")
