import Foundation
import Testing
@testable import Spectro

@Suite("Schema Protocol")
struct SchemaTests {

    @Test("Schema provides tableName")
    func tableName() {
        #expect(TestUser.tableName == "test_users")
        #expect(TestPost.tableName == "test_posts")
    }

    @Test("Schema provides default init")
    func defaultInit() {
        let user = TestUser()
        #expect(user.name == "")
        #expect(user.email == "")
        #expect(user.age == 0)
        #expect(user.isActive == true)
    }

    @Test("SchemaBuilder.build populates fields from dictionary")
    func schemaBuilderBuild() {
        let id = UUID()
        let user = TestUser.build(from: [
            "id": id,
            "name": "Alice",
            "email": "alice@example.com",
            "age": 30,
            "isActive": false,
        ])
        #expect(user.id == id)
        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
        #expect(user.age == 30)
        #expect(user.isActive == false)
    }

    @Test("SchemaBuilder.build ignores unknown keys")
    func schemaBuilderUnknownKeys() {
        let user = TestUser.build(from: [
            "name": "Bob",
            "nonexistent": 42,
        ])
        #expect(user.name == "Bob")
        #expect(user.age == 0)
    }

    @Test("SchemaRegistry extracts metadata via Mirror")
    func schemaRegistryMetadata() async {
        let metadata = await SchemaRegistry.shared.register(TestUser.self)
        #expect(metadata.tableName == "test_users")
        #expect(metadata.primaryKeyField == "id")

        let fieldNames = metadata.fields.map(\.name)
        #expect(fieldNames.contains("id"))
        #expect(fieldNames.contains("name"))
        #expect(fieldNames.contains("email"))
        #expect(fieldNames.contains("age"))
        #expect(fieldNames.contains("isActive"))
        #expect(fieldNames.contains("createdAt"))
    }

    @Test("SchemaRegistry identifies field types correctly")
    func fieldTypes() async {
        let metadata = await SchemaRegistry.shared.register(TestUser.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["id"]?.fieldType == .uuid)
        #expect(fieldMap["id"]?.isPrimaryKey == true)
        #expect(fieldMap["name"]?.fieldType == .string)
        #expect(fieldMap["age"]?.fieldType == .int)
        #expect(fieldMap["isActive"]?.fieldType == .bool)
        #expect(fieldMap["createdAt"]?.fieldType == .date)
        #expect(fieldMap["createdAt"]?.isTimestamp == true)
    }

    @Test("SchemaRegistry identifies foreign keys")
    func foreignKeyDetection() async {
        let metadata = await SchemaRegistry.shared.register(TestPost.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["userId"]?.isForeignKey == true)
        #expect(fieldMap["userId"]?.fieldType == .uuid)
    }

    @Test("SchemaRegistry detects optional columns as nullable")
    func optionalColumnsNullable() async {
        let metadata = await SchemaRegistry.shared.register(TestUserWithBio.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["bio"] != nil, "bio field must be registered")
        #expect(fieldMap["bio"]?.fieldType == .string)
        #expect(fieldMap["bio"]?.isNullable == true)
        #expect(fieldMap["name"]?.isNullable == false)
    }

    @Test("SchemaRegistry snake_cases database column names")
    func databaseNames() async {
        let metadata = await SchemaRegistry.shared.register(TestUser.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["isActive"]?.databaseName == "is_active")
        #expect(fieldMap["createdAt"]?.databaseName == "created_at")
    }
}

@Suite("fromSync column name override via ColumnNameOverridable")
struct FromSyncColumnOverrideTests {

    @Test("Mirror discovers ColumnNameOverridable override from @Column wrapper")
    func mirrorDiscoversColumnOverride() {
        let instance = TestColumnOverride()
        let mirror = Mirror(reflecting: instance)

        var resolvedColumns: [String: String] = [:]
        for child in mirror.children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            let dbColumn: String
            if let overridable = child.value as? ColumnNameOverridable,
               let override = overridable.columnName {
                dbColumn = override
            } else {
                dbColumn = fieldName.snakeCase()
            }
            resolvedColumns[fieldName] = dbColumn
        }

        // @Column("display_name") var name → "display_name"
        #expect(resolvedColumns["name"] == "display_name")
        // @Column var email (no override) → "email"
        #expect(resolvedColumns["email"] == "email")
        // @ID var id → "id"
        #expect(resolvedColumns["id"] == "id")
    }

    @Test("ForeignKey with column override is detected by ColumnNameOverridable")
    func foreignKeyColumnOverride() {
        let fk = ForeignKey<UUID>("custom_fk_col")
        #expect((fk as ColumnNameOverridable).columnName == "custom_fk_col")
    }

    @Test("ForeignKey without override returns nil columnName")
    func foreignKeyNoOverride() {
        let fk = ForeignKey<UUID>()
        #expect((fk as ColumnNameOverridable).columnName == nil)
    }

    @Test("Column without override returns nil columnName")
    func columnNoOverride() {
        let col = Column<String>(wrappedValue: "test")
        #expect((col as ColumnNameOverridable).columnName == nil)
    }
}

@Suite("Phase 1D: Schema DSL Improvements")
struct Phase1DSchemaTests {

    @Test("@Column with custom name override sets databaseName")
    func columnNameOverride() async {
        let metadata = await SchemaRegistry.shared.register(TestColumnOverride.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        // "name" property was declared as @Column("display_name") var name: String
        #expect(fieldMap["name"] != nil, "name field must be registered")
        #expect(fieldMap["name"]?.databaseName == "display_name")
        #expect(fieldMap["name"]?.fieldType == .string)

        // "email" has no override — should use default snake_case
        #expect(fieldMap["email"]?.databaseName == "email")
    }

    @Test("Non-optional Column<UUID> is registered by SchemaRegistry")
    func columnUuidNotDropped() async {
        let metadata = await SchemaRegistry.shared.register(TestWithUuidColumn.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["externalId"] != nil, "Column<UUID> must not be silently dropped")
        #expect(fieldMap["externalId"]?.fieldType == .uuid)
        #expect(fieldMap["externalId"]?.isPrimaryKey == false)
        #expect(fieldMap["externalId"]?.isForeignKey == false)
        #expect(fieldMap["externalId"]?.databaseName == "external_id")
    }

    @Test("Column<UUID> is distinct from @ID in SchemaRegistry metadata")
    func columnUuidDistinctFromID() async {
        let metadata = await SchemaRegistry.shared.register(TestWithUuidColumn.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        // @ID is the primary key
        #expect(fieldMap["id"]?.isPrimaryKey == true)
        #expect(fieldMap["id"]?.fieldType == .uuid)

        // @Column var externalId: UUID is NOT a primary key
        #expect(fieldMap["externalId"]?.isPrimaryKey == false)
        #expect(fieldMap["externalId"]?.fieldType == .uuid)
    }
}

@Suite("@Schema Macro")
struct SchemaMacroTests {

    @Test("Macro generates tableName")
    func macroTableName() {
        #expect(TestMacroUser.tableName == "test_macro_users")
    }

    @Test("Macro generates init() with correct defaults")
    func macroDefaultInit() {
        let user = TestMacroUser()
        #expect(user.name == "")
        #expect(user.email == "")
        #expect(user.bio == nil)
    }

    @Test("Macro generates convenience init for @Column properties")
    func macroConvenienceInit() {
        let user = TestMacroUser(name: "Alice", email: "alice@test.com")
        #expect(user.name == "Alice")
        #expect(user.email == "alice@test.com")
        #expect(user.bio == nil)
    }

    @Test("Macro convenience init accepts optional columns")
    func macroConvenienceInitOptional() {
        let user = TestMacroUser(name: "Bob", email: "bob@test.com", bio: "Hello")
        #expect(user.name == "Bob")
        #expect(user.bio == "Hello")
    }

    @Test("Macro convenience init auto-fills @ID and @Timestamp")
    func macroAutoFillsIDAndTimestamp() {
        let before = Date()
        let user = TestMacroUser(name: "C", email: "c@test.com")
        let after = Date()
        #expect(user.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(user.createdAt >= before)
        #expect(user.createdAt <= after)
    }

    @Test("Macro generates build(from:) that round-trips values")
    func macroBuild() {
        let id = UUID()
        let date = Date()
        let user = TestMacroUser.build(from: [
            "id": id,
            "name": "Alice",
            "email": "alice@example.com",
            "bio": "Hi there",
            "createdAt": date,
        ])
        #expect(user.id == id)
        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
        #expect(user.bio == "Hi there")
        #expect(user.createdAt == date)
    }

    @Test("Macro build(from:) handles nil optional correctly")
    func macroBuildNilOptional() {
        let user = TestMacroUser.build(from: [
            "name": "Bob",
            "email": "bob@example.com",
        ])
        #expect(user.name == "Bob")
        #expect(user.bio == nil)
    }

    @Test("SchemaRegistry detects macro-generated schema fields")
    func macroSchemaRegistry() async {
        let metadata = await SchemaRegistry.shared.register(TestMacroUser.self)
        #expect(metadata.tableName == "test_macro_users")
        let fieldNames = metadata.fields.map(\.name)
        #expect(fieldNames.contains("id"))
        #expect(fieldNames.contains("name"))
        #expect(fieldNames.contains("email"))
        #expect(fieldNames.contains("bio"))
        #expect(fieldNames.contains("createdAt"))
    }

    @Test("SchemaRegistry detects nullable bio on macro schema")
    func macroNullableField() async {
        let metadata = await SchemaRegistry.shared.register(TestMacroUser.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })
        #expect(fieldMap["bio"]?.isNullable == true)
        #expect(fieldMap["bio"]?.fieldType == .string)
        #expect(fieldMap["name"]?.isNullable == false)
    }
}

@Suite("Phase 2: Non-UUID Primary Key Metadata")
struct Phase2NonUUIDPrimaryKeyTests {

    @Test("SchemaRegistry detects Int primary key with correct fieldType")
    func intPrimaryKeyMetadata() async {
        let metadata = await SchemaRegistry.shared.register(IntPKItem.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(metadata.tableName == "int_pk_items")
        #expect(metadata.primaryKeyField == "id")

        #expect(fieldMap["id"]?.fieldType == .int)
        #expect(fieldMap["id"]?.isPrimaryKey == true)
        #expect(fieldMap["id"]?.isForeignKey == false)

        #expect(fieldMap["name"]?.fieldType == .string)
        #expect(fieldMap["name"]?.isPrimaryKey == false)
    }

    @Test("SchemaRegistry detects String primary key with correct fieldType")
    func stringPrimaryKeyMetadata() async {
        let metadata = await SchemaRegistry.shared.register(StringPKItem.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(metadata.tableName == "string_pk_items")
        #expect(metadata.primaryKeyField == "id")

        #expect(fieldMap["id"]?.fieldType == .string)
        #expect(fieldMap["id"]?.isPrimaryKey == true)
        #expect(fieldMap["id"]?.isForeignKey == false)

        #expect(fieldMap["name"]?.fieldType == .string)
        #expect(fieldMap["name"]?.isPrimaryKey == false)
    }

    @Test("SchemaRegistry detects Int foreign key with correct fieldType")
    func intForeignKeyMetadata() async {
        let metadata = await SchemaRegistry.shared.register(IntFKChild.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["parentId"]?.fieldType == .int)
        #expect(fieldMap["parentId"]?.isForeignKey == true)
        #expect(fieldMap["parentId"]?.isPrimaryKey == false)
        #expect(fieldMap["parentId"]?.databaseName == "parent_id")
    }

    @Test("Int PK SchemaBuilder.build populates fields from dictionary")
    func intPKBuild() {
        let item = IntPKItem.build(from: [
            "id": 42,
            "name": "Test Item",
        ])
        #expect(item.id == 42)
        #expect(item.name == "Test Item")
    }

    @Test("String PK SchemaBuilder.build populates fields from dictionary")
    func stringPKBuild() {
        let item = StringPKItem.build(from: [
            "id": "custom-slug",
            "name": "Test Item",
        ])
        #expect(item.id == "custom-slug")
        #expect(item.name == "Test Item")
    }

    @Test("Int PK default init uses correct defaults")
    func intPKDefaultInit() {
        let item = IntPKItem()
        #expect(item.id == 0)
        #expect(item.name == "")
    }

    @Test("String PK default init uses correct defaults")
    func stringPKDefaultInit() {
        let item = StringPKItem()
        #expect(item.id == "")
        #expect(item.name == "")
    }
}

@Suite("DynamicSchema")
struct DynamicSchemaTests {
    class TestDynamicUser: DynamicSchema, @unchecked Sendable {
        override class var tableName: String { "dynamic_users" }
    }

    @Test("DynamicSchema provides tableName")
    func tableName() {
        #expect(TestDynamicUser.tableName == "dynamic_users")
    }

    @Test("DynamicSchema supports dynamic member access")
    func dynamicMemberAccess() {
        let user = TestDynamicUser()
        user.name = "Alice"
        user.age = 30
        #expect(user.name as? String == "Alice")
        #expect(user.age as? Int == 30)
    }

    @Test("DynamicSchema returns nil for unset attributes")
    func unsetAttributes() {
        let user = TestDynamicUser()
        #expect(user.name == nil)
    }
}
