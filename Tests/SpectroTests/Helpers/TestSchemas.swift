import Foundation
@testable import Spectro

// MARK: - Test Schema Definitions

struct TestUser: Schema, SchemaBuilder {
    static let tableName = "test_users"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \TestUser.id: "id",
        \TestUser.name: "name",
        \TestUser.email: "email",
        \TestUser.age: "age",
        \TestUser.isActive: "isActive",
        \TestUser.createdAt: "createdAt",
    ]

    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Column var age: Int
    @Column var isActive: Bool
    @Timestamp var createdAt: Date

    init() {
        self.id = UUID()
        self.name = ""
        self.email = ""
        self.age = 0
        self.isActive = true
        self.createdAt = Date()
    }

    init(name: String, email: String, age: Int, isActive: Bool = true) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.age = age
        self.isActive = isActive
        self.createdAt = Date()
    }

    static func build(from values: [String: Any]) -> TestUser {
        var user = TestUser()
        if let v = values["id"] as? UUID { user.id = v }
        if let v = values["name"] as? String { user.name = v }
        if let v = values["email"] as? String { user.email = v }
        if let v = values["age"] as? Int { user.age = v }
        if let v = values["isActive"] as? Bool { user.isActive = v }
        if let v = values["createdAt"] as? Date { user.createdAt = v }
        return user
    }
}

struct TestUserWithBio: Schema, SchemaBuilder {
    static let tableName = "test_users_bio"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \TestUserWithBio.id: "id",
        \TestUserWithBio.name: "name",
        \TestUserWithBio.email: "email",
        \TestUserWithBio.bio: "bio",
    ]

    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Column var bio: String?

    init() {
        self.id = UUID()
        self.name = ""
        self.email = ""
        self.bio = nil
    }

    init(name: String, email: String, bio: String? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.bio = bio
    }

    static func build(from values: [String: Any]) -> TestUserWithBio {
        var user = TestUserWithBio()
        if let v = values["id"] as? UUID { user.id = v }
        if let v = values["name"] as? String { user.name = v }
        if let v = values["email"] as? String { user.email = v }
        user.bio = values["bio"] as? String
        return user
    }
}

// MARK: - Macro-generated Schema (no manual boilerplate)

@Schema("test_macro_users")
struct TestMacroUser {
    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Column var bio: String?
    @Timestamp var createdAt: Date
}

// MARK: - Phase 1D Test Schemas

/// Schema with a custom column name override via @Column("display_name")
struct TestColumnOverride: Schema, SchemaBuilder {
    static let tableName = "test_column_overrides"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \TestColumnOverride.id: "id",
        \TestColumnOverride.name: "name",
        \TestColumnOverride.email: "email",
    ]

    @ID var id: UUID
    @Column("display_name") var name: String = ""
    @Column var email: String = ""

    init() {
        self.id = UUID()
    }

    static func build(from values: [String: Any]) -> TestColumnOverride {
        var entity = TestColumnOverride()
        if let v = values["id"] as? UUID { entity.id = v }
        if let v = values["name"] as? String { entity.name = v }
        if let v = values["email"] as? String { entity.email = v }
        return entity
    }
}

/// Schema with a non-optional Column<UUID> to verify it's not dropped by SchemaRegistry
struct TestWithUuidColumn: Schema, SchemaBuilder {
    static let tableName = "test_with_uuid_columns"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \TestWithUuidColumn.id: "id",
        \TestWithUuidColumn.externalId: "externalId",
        \TestWithUuidColumn.name: "name",
    ]

    @ID var id: UUID
    @Column var externalId: UUID
    @Column var name: String

    init() {
        self.id = UUID()
        self.externalId = UUID()
        self.name = ""
    }

    static func build(from values: [String: Any]) -> TestWithUuidColumn {
        var entity = TestWithUuidColumn()
        if let v = values["id"] as? UUID { entity.id = v }
        if let v = values["externalId"] as? UUID { entity.externalId = v }
        if let v = values["name"] as? String { entity.name = v }
        return entity
    }
}

// MARK: - Non-UUID Primary Key Test Schemas

/// Schema with an Int (SERIAL) primary key for testing non-UUID PK support.
struct IntPKItem: Schema, SchemaBuilder {
    static let tableName = "int_pk_items"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \IntPKItem.id: "id",
        \IntPKItem.name: "name",
    ]

    @ID var id: Int
    @Column var name: String

    init() {
        self.id = 0
        self.name = ""
    }

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    init(name: String) {
        self.id = 0
        self.name = name
    }

    static func build(from values: [String: Any]) -> IntPKItem {
        var item = IntPKItem()
        if let v = values["id"] as? Int { item.id = v }
        if let v = values["name"] as? String { item.name = v }
        return item
    }
}

/// Schema with a String (TEXT) primary key for testing non-UUID PK support.
struct StringPKItem: Schema, SchemaBuilder {
    static let tableName = "string_pk_items"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \StringPKItem.id: "id",
        \StringPKItem.name: "name",
    ]

    @ID var id: String
    @Column var name: String

    init() {
        self.id = ""
        self.name = ""
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    static func build(from values: [String: Any]) -> StringPKItem {
        var item = StringPKItem()
        if let v = values["id"] as? String { item.id = v }
        if let v = values["name"] as? String { item.name = v }
        return item
    }
}

/// Schema with an Int foreign key for testing non-UUID FK support.
struct IntFKChild: Schema, SchemaBuilder {
    static let tableName = "int_fk_children"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \IntFKChild.id: "id",
        \IntFKChild.label: "label",
        \IntFKChild.parentId: "parentId",
    ]

    @ID var id: UUID
    @Column var label: String
    @ForeignKey var parentId: Int

    init() {
        self.id = UUID()
        self.label = ""
        self.parentId = 0
    }

    static func build(from values: [String: Any]) -> IntFKChild {
        var item = IntFKChild()
        if let v = values["id"] as? UUID { item.id = v }
        if let v = values["label"] as? String { item.label = v }
        if let v = values["parentId"] as? Int { item.parentId = v }
        return item
    }
}

// MARK: - Manual Schema Definitions (continued)

// MARK: - Relationship Test Schemas (for preload integration tests)

@Schema("rel_users")
struct RelUser {
    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Timestamp var createdAt: Date
    @HasMany var posts: [RelPost]
    @HasOne var profile: RelProfile?
    @ManyToMany(junctionTable: "rel_user_tags", parentFK: "relUserId", relatedFK: "relTagId")
    var tags: [RelTag]
}

@Schema("rel_posts")
struct RelPost {
    @ID var id: UUID
    @Column var title: String
    @Column var body: String
    @ForeignKey var relUserId: UUID
    @Timestamp var createdAt: Date
    @BelongsTo var relUser: RelUser?
}

@Schema("rel_profiles")
struct RelProfile {
    @ID var id: UUID
    @Column var bio: String
    @ForeignKey var relUserId: UUID
    @Timestamp var createdAt: Date
    @BelongsTo var relUser: RelUser?
}

@Schema("rel_tags")
struct RelTag {
    @ID var id: UUID
    @Column var name: String
}

@Schema("rel_user_tags")
struct RelUserTag {
    @ID var id: UUID
    @ForeignKey var relUserId: UUID
    @ForeignKey var relTagId: UUID
}

// MARK: - Manual Schema Definitions (continued)

struct TestPost: Schema, SchemaBuilder {
    static let tableName = "test_posts"

    nonisolated(unsafe) static let _keyPathToColumn: [AnyKeyPath: String] = [
        \TestPost.id: "id",
        \TestPost.title: "title",
        \TestPost.body: "body",
        \TestPost.userId: "userId",
        \TestPost.createdAt: "createdAt",
    ]

    @ID var id: UUID
    @Column var title: String
    @Column var body: String
    @ForeignKey var userId: UUID
    @Timestamp var createdAt: Date

    init() {
        self.id = UUID()
        self.title = ""
        self.body = ""
        self.userId = UUID()
        self.createdAt = Date()
    }

    init(title: String, body: String, userId: UUID) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.userId = userId
        self.createdAt = Date()
    }

    static func build(from values: [String: Any]) -> TestPost {
        var post = TestPost()
        if let v = values["id"] as? UUID { post.id = v }
        if let v = values["title"] as? String { post.title = v }
        if let v = values["body"] as? String { post.body = v }
        if let v = values["userId"] as? UUID { post.userId = v }
        if let v = values["createdAt"] as? Date { post.createdAt = v }
        return post
    }
}
