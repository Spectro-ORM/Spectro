import Foundation
import Testing
@testable import Spectro

@Suite("Relationships")
struct RelationshipTests {

    // MARK: - RelationshipInfo

    @Test("RelationshipInfo stores metadata")
    func relationshipInfoMetadata() {
        let info = RelationshipInfo(
            name: "posts",
            relatedTypeName: "Post",
            kind: .hasMany,
            foreignKey: "userId"
        )
        #expect(info.name == "posts")
        #expect(info.relatedTypeName == "Post")
        #expect(info.kind == .hasMany)
        #expect(info.foreignKey == "userId")
    }

    @Test("RelationshipInfo allows nil foreignKey")
    func relationshipInfoNilFK() {
        let info = RelationshipInfo(
            name: "profile",
            relatedTypeName: "Profile",
            kind: .hasOne,
            foreignKey: nil
        )
        #expect(info.foreignKey == nil)
    }

    // MARK: - SpectroLazyRelation State Machine

    @Test("SpectroLazyRelation starts as not loaded")
    func lazyRelationInitialState() {
        let relation = SpectroLazyRelation<[TestPost]>(
            relationshipInfo: RelationshipInfo(
                name: "posts", relatedTypeName: "TestPost",
                kind: .hasMany, foreignKey: nil
            )
        )
        #expect(!relation.isLoaded)
        #expect(relation.value == nil)
    }

    @Test("SpectroLazyRelation.withLoaded transitions to loaded state")
    func lazyRelationWithLoaded() {
        let relation = SpectroLazyRelation<[TestPost]>(
            relationshipInfo: RelationshipInfo(
                name: "posts", relatedTypeName: "TestPost",
                kind: .hasMany, foreignKey: nil
            )
        )
        let loaded = relation.withLoaded([])
        #expect(loaded.isLoaded)
        #expect(loaded.value != nil)
        #expect(loaded.value?.isEmpty == true)
    }

    @Test("SpectroLazyRelation preserves relationship info after loading")
    func lazyRelationPreservesInfo() {
        let info = RelationshipInfo(
            name: "posts", relatedTypeName: "TestPost",
            kind: .hasMany, foreignKey: "userId"
        )
        let relation = SpectroLazyRelation<[TestPost]>(relationshipInfo: info)
        let loaded = relation.withLoaded([])
        #expect(loaded.relationshipInfo.name == "posts")
        #expect(loaded.relationshipInfo.foreignKey == "userId")
    }

    @Test("SpectroLazyRelation default init")
    func lazyRelationDefaultInit() {
        let relation = SpectroLazyRelation<[TestPost]>()
        #expect(!relation.isLoaded)
    }

    // MARK: - Property Wrappers

    @Test("HasMany is not loaded by default")
    func hasManyDefaultValue() {
        let wrapper = HasMany<TestPost>()
        #expect(!wrapper.projectedValue.isLoaded)
    }

    @Test("HasOne is not loaded by default")
    func hasOneDefaultValue() {
        let wrapper = HasOne<TestPost>()
        #expect(!wrapper.projectedValue.isLoaded)
    }

    @Test("BelongsTo is not loaded by default")
    func belongsToDefaultValue() {
        let wrapper = BelongsTo<TestUser>()
        #expect(!wrapper.projectedValue.isLoaded)
    }

    // MARK: - Foreign Key Override

    @Test("HasMany stores custom foreignKey")
    func hasManyForeignKeyOverride() {
        let wrapper = HasMany<TestPost>(wrappedValue: [], foreignKey: "author_id")
        #expect(wrapper.foreignKey == "author_id")
    }

    @Test("HasMany without foreignKey defaults to nil")
    func hasManyForeignKeyDefault() {
        let wrapper = HasMany<TestPost>()
        #expect(wrapper.foreignKey == nil)
    }

    @Test("HasOne stores custom foreignKey")
    func hasOneForeignKeyOverride() {
        let wrapper = HasOne<TestPost>(foreignKey: "author_id")
        #expect(wrapper.foreignKey == "author_id")
    }

    @Test("BelongsTo stores custom foreignKey")
    func belongsToForeignKeyOverride() {
        let wrapper = BelongsTo<TestUser>(foreignKey: "writer_id")
        #expect(wrapper.foreignKey == "writer_id")
    }

    @Test("HasMany foreignKey propagates to relationshipInfo")
    func hasManyForeignKeyInRelationshipInfo() {
        let wrapper = HasMany<TestPost>(wrappedValue: [], foreignKey: "author_id")
        #expect(wrapper.projectedValue.relationshipInfo.foreignKey == "author_id")
        #expect(wrapper.projectedValue.relationshipInfo.kind == .hasMany)
    }

    // MARK: - Conventional FK

    @Test("Conventional foreign key derivation")
    func conventionalForeignKey() {
        let fk = PreloadQuery<TestUser>.conventionalForeignKey(for: TestUser.self)
        #expect(fk == "testUserId")
    }

    @Test("BelongsTo FK derives from related type, not parent type")
    func belongsToForeignKeyDerivation() {
        // For Post belongsTo User, FK should derive from User → "relUserId", not from Post → "relPostId"
        let fk = PreloadQuery<RelPost>.conventionalForeignKey(for: RelUser.self)
        #expect(fk == "relUserId")
    }
}
