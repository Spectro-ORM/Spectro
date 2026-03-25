/// Generates a complete `Schema` + `SchemaBuilder` conformance for a struct.
///
/// Annotate your struct with `@Schema("table_name")` and the macro generates:
/// - `static let tableName` — from the string argument
/// - `init()` — default initializer with type-appropriate defaults
/// - `init(column params...)` — convenience initializer for `@Column`/`@ForeignKey` properties
/// - `SchemaBuilder.build(from:)` — row-mapping from `[String: Any]`
///
/// The struct automatically conforms to `Schema` and `SchemaBuilder` — no manual
/// protocol conformance needed.
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
/// The macro expands to (conceptually):
///
/// ```swift
/// struct User {
///     @ID var id: UUID
///     @Column var name: String
///     @Column var email: String
///     @Column var bio: String?
///     @Timestamp var createdAt: Date
///
///     static let tableName = "users"
///
///     init() {
///         self.id = UUID()
///         self.name = ""
///         self.email = ""
///         self.bio = nil
///         self.createdAt = Date()
///     }
///
///     init(name: String, email: String, bio: String? = nil) {
///         self.id = UUID()
///         self.name = name
///         self.email = email
///         self.bio = bio
///         self.createdAt = Date()
///     }
/// }
///
/// extension User: Schema, SchemaBuilder {
///     public static func build(from values: [String: Any]) -> User {
///         var instance = User()
///         if let __v = values["id"]        as? UUID   { instance.id        = __v }
///         if let __v = values["name"]      as? String { instance.name      = __v }
///         if let __v = values["email"]     as? String { instance.email     = __v }
///         instance.bio = values["bio"] as? String
///         if let __v = values["createdAt"] as? Date   { instance.createdAt = __v }
///         return instance
///     }
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
@attached(extension, conformances: Schema, SchemaBuilder, names: named(build))
public macro Schema(_ tableName: String) = #externalMacro(module: "SpectroMacros", type: "SchemaMacro")
