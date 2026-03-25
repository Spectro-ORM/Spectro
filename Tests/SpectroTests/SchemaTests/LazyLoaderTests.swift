import Foundation
import Testing
@testable import Spectro

// MARK: - Unit Tests (no database needed)

@Suite("LazyLoader Unit")
struct LazyLoaderUnitTests {

    @Test("load without loader throws notImplemented error")
    func loadWithoutLoaderThrowsError() async throws {
        var relation = SpectroLazyRelation<[RelPost]>(
            relationshipInfo: RelationshipInfo(
                name: "posts",
                relatedTypeName: "RelPost",
                kind: .hasMany,
                foreignKey: "rel_user_id"
            )
        )

        // We need a GenericDatabaseRepo to call load(using:), but the loader is nil
        // so it should throw before any database access happens.
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()

        do {
            let _ = try await relation.load(using: repo)
            Issue.record("Expected SpectroError.notImplemented to be thrown")
        } catch let error as SpectroError {
            if case .notImplemented(let message) = error {
                #expect(message.contains("no loader"))
                #expect(message.contains("RelPost"))
            } else {
                Issue.record("Expected .notImplemented but got \(error)")
            }
        }

        await spectro.shutdown()
    }

    @Test("withLoader creates a new relation that has a loader")
    func withLoaderCreatesNewRelation() async throws {
        let relation = SpectroLazyRelation<[RelPost]>(
            relationshipInfo: RelationshipInfo(
                name: "posts",
                relatedTypeName: "RelPost",
                kind: .hasMany,
                foreignKey: "rel_user_id"
            )
        )

        // Original is not loaded
        #expect(!relation.isLoaded)

        // Attach a mock loader that returns a fixed array
        let withLoader = relation.withLoader { _ in
            return [] as [RelPost]
        }

        // The new relation should still not be loaded (loader is attached but not called)
        #expect(!withLoader.isLoaded)

        // Relationship info should be preserved
        #expect(withLoader.relationshipInfo.name == "posts")
        #expect(withLoader.relationshipInfo.foreignKey == "rel_user_id")
        #expect(withLoader.relationshipInfo.kind == .hasMany)
    }

    @Test("load transitions through states: notLoaded -> loading -> loaded")
    func loadStateTransitions() async throws {
        let info = RelationshipInfo(
            name: "posts",
            relatedTypeName: "RelPost",
            kind: .hasMany,
            foreignKey: "rel_user_id"
        )
        var relation = SpectroLazyRelation<[String]>(relationshipInfo: info)

        // Initial state: notLoaded
        if case .notLoaded = relation.state {
            // expected
        } else {
            Issue.record("Expected initial state to be .notLoaded, got \(relation.state)")
        }
        #expect(!relation.isLoaded)
        #expect(relation.value == nil)

        // Attach a mock loader
        relation = relation.withLoader { _ in
            return ["post1", "post2"]
        }

        // Still notLoaded before calling load
        if case .notLoaded = relation.state {
            // expected
        } else {
            Issue.record("Expected state before load to be .notLoaded, got \(relation.state)")
        }

        // We need a repo to call load(using:) -- create a real one even though
        // the mock loader ignores it.
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()

        let result = try await relation.load(using: repo)

        // After load: should be loaded with the data
        #expect(result == ["post1", "post2"])
        if case .loaded(let data) = relation.state {
            #expect(data == ["post1", "post2"])
        } else {
            Issue.record("Expected state after load to be .loaded, got \(relation.state)")
        }
        #expect(relation.isLoaded)
        #expect(relation.value == ["post1", "post2"])

        await spectro.shutdown()
    }

    @Test("load returns cached value when already loaded")
    func loadReturnsCachedValue() async throws {
        let info = RelationshipInfo(
            name: "items",
            relatedTypeName: "String",
            kind: .hasMany,
            foreignKey: nil
        )

        let counter = MutableCounter()

        var relation = SpectroLazyRelation<[String]>(relationshipInfo: info)
            .withLoader { _ in
                await counter.increment()
                return ["a", "b"]
            }

        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()

        // First load
        let first = try await relation.load(using: repo)
        #expect(first == ["a", "b"])

        // Second load should return cached value without calling loader again
        let second = try await relation.load(using: repo)
        #expect(second == ["a", "b"])

        let count = await counter.value
        #expect(count == 1, "Loader should only be called once; cached value should be returned on second call")

        await spectro.shutdown()
    }

    @Test("load sets error state on loader failure")
    func loadSetsErrorStateOnFailure() async throws {
        let info = RelationshipInfo(
            name: "posts",
            relatedTypeName: "RelPost",
            kind: .hasMany,
            foreignKey: nil
        )

        var relation = SpectroLazyRelation<[String]>(relationshipInfo: info)
            .withLoader { _ in
                throw SpectroError.internalError("simulated failure")
            }

        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()

        do {
            let _ = try await relation.load(using: repo)
            Issue.record("Expected loader to throw")
        } catch let error as SpectroError {
            if case .internalError(let msg) = error {
                #expect(msg == "simulated failure")
            } else {
                Issue.record("Expected .internalError but got \(error)")
            }
        }

        // State should be .error
        if case .error = relation.state {
            // expected
        } else {
            Issue.record("Expected state to be .error after failed load, got \(relation.state)")
        }

        await spectro.shutdown()
    }
}

/// Actor-isolated counter for tracking how many times a closure is called.
private actor MutableCounter {
    var value: Int = 0
    func increment() { value += 1 }
}

// MARK: - Integration Tests (need database)

extension DatabaseIntegrationTests {
@Suite("LazyLoader Integration")
struct LazyLoaderIntegrationTests {

    private func withRelationshipTables(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()

        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "rel_users" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL DEFAULT '',
                "email" TEXT NOT NULL DEFAULT '',
                "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "rel_posts" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "title" TEXT NOT NULL DEFAULT '',
                "body" TEXT NOT NULL DEFAULT '',
                "rel_user_id" UUID NOT NULL,
                "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "rel_profiles" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "bio" TEXT NOT NULL DEFAULT '',
                "rel_user_id" UUID NOT NULL,
                "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)

        try await repo.executeRawSQL("TRUNCATE \"rel_profiles\", \"rel_posts\", \"rel_users\"")

        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    // MARK: - hasManyLoader

    @Test("hasManyLoader returns related child records")
    func hasManyLoaderReturnsRelatedRecords() async throws {
        try await withRelationshipTables { repo in
            // Insert parent
            let alice = try await repo.insert(RelUser(name: "Alice", email: "alice@test.com"))
            let bob = try await repo.insert(RelUser(name: "Bob", email: "bob@test.com"))

            // Insert children for Alice
            let _ = try await repo.insert(RelPost(title: "Alice Post 1", body: "Body 1", relUserId: alice.id))
            let _ = try await repo.insert(RelPost(title: "Alice Post 2", body: "Body 2", relUserId: alice.id))
            // Insert child for Bob
            let _ = try await repo.insert(RelPost(title: "Bob Post 1", body: "Body 3", relUserId: bob.id))

            // Create a hasManyLoader for Alice's posts
            let loader: @Sendable (GenericDatabaseRepo) async throws -> [RelPost] =
                SpectroLazyRelation<[RelPost]>.hasManyLoader(
                    parentId: alice.id,
                    foreignKey: "rel_user_id"
                )

            var relation = SpectroLazyRelation<[RelPost]>(
                relationshipInfo: RelationshipInfo(
                    name: "posts",
                    relatedTypeName: "RelPost",
                    kind: .hasMany,
                    foreignKey: "rel_user_id"
                )
            ).withLoader(loader)

            // Load the relationship
            let posts = try await relation.load(using: repo)

            #expect(posts.count == 2)
            let titles = Set(posts.map(\.title))
            #expect(titles.contains("Alice Post 1"))
            #expect(titles.contains("Alice Post 2"))

            // Verify it's now in loaded state
            #expect(relation.isLoaded)
        }
    }

    @Test("hasManyLoader returns empty array when no children exist")
    func hasManyLoaderReturnsEmptyWhenNoChildren() async throws {
        try await withRelationshipTables { repo in
            let charlie = try await repo.insert(RelUser(name: "Charlie", email: "charlie@test.com"))

            let loader: @Sendable (GenericDatabaseRepo) async throws -> [RelPost] =
                SpectroLazyRelation<[RelPost]>.hasManyLoader(
                    parentId: charlie.id,
                    foreignKey: "rel_user_id"
                )

            var relation = SpectroLazyRelation<[RelPost]>(
                relationshipInfo: RelationshipInfo(
                    name: "posts",
                    relatedTypeName: "RelPost",
                    kind: .hasMany,
                    foreignKey: "rel_user_id"
                )
            ).withLoader(loader)

            let posts = try await relation.load(using: repo)
            #expect(posts.isEmpty)
            #expect(relation.isLoaded)
        }
    }

    // MARK: - hasOneLoader

    @Test("hasOneLoader returns single related record")
    func hasOneLoaderReturnsRelatedRecord() async throws {
        try await withRelationshipTables { repo in
            let alice = try await repo.insert(RelUser(name: "Alice", email: "alice@test.com"))
            let _ = try await repo.insert(RelProfile(bio: "Alice's bio", relUserId: alice.id))

            let loader: @Sendable (GenericDatabaseRepo) async throws -> RelProfile? =
                SpectroLazyRelation<RelProfile?>.hasOneLoader(
                    parentId: alice.id,
                    foreignKey: "rel_user_id"
                )

            var relation = SpectroLazyRelation<RelProfile?>(
                relationshipInfo: RelationshipInfo(
                    name: "profile",
                    relatedTypeName: "RelProfile",
                    kind: .hasOne,
                    foreignKey: "rel_user_id"
                )
            ).withLoader(loader)

            let profile = try await relation.load(using: repo)
            #expect(profile != nil)
            #expect(profile?.bio == "Alice's bio")
            #expect(relation.isLoaded)
        }
    }

    @Test("hasOneLoader returns nil when no related record exists")
    func hasOneLoaderReturnsNilWhenNoRecord() async throws {
        try await withRelationshipTables { repo in
            let bob = try await repo.insert(RelUser(name: "Bob", email: "bob@test.com"))

            let loader: @Sendable (GenericDatabaseRepo) async throws -> RelProfile? =
                SpectroLazyRelation<RelProfile?>.hasOneLoader(
                    parentId: bob.id,
                    foreignKey: "rel_user_id"
                )

            var relation = SpectroLazyRelation<RelProfile?>(
                relationshipInfo: RelationshipInfo(
                    name: "profile",
                    relatedTypeName: "RelProfile",
                    kind: .hasOne,
                    foreignKey: "rel_user_id"
                )
            ).withLoader(loader)

            let profile = try await relation.load(using: repo)
            #expect(profile == nil)
            #expect(relation.isLoaded)
        }
    }

    // MARK: - belongsToLoader

    @Test("belongsToLoader returns parent record")
    func belongsToLoaderReturnsParent() async throws {
        try await withRelationshipTables { repo in
            let alice = try await repo.insert(RelUser(name: "Alice", email: "alice@test.com"))
            let post = try await repo.insert(RelPost(title: "Alice Post", body: "Body", relUserId: alice.id))

            let loader: @Sendable (GenericDatabaseRepo) async throws -> RelUser? =
                SpectroLazyRelation<RelUser?>.belongsToLoader(
                    foreignKeyValue: post.relUserId
                )

            var relation = SpectroLazyRelation<RelUser?>(
                relationshipInfo: RelationshipInfo(
                    name: "relUser",
                    relatedTypeName: "RelUser",
                    kind: .belongsTo,
                    foreignKey: "rel_user_id"
                )
            ).withLoader(loader)

            let user = try await relation.load(using: repo)
            #expect(user != nil)
            #expect(user?.name == "Alice")
            #expect(user?.email == "alice@test.com")
            #expect(relation.isLoaded)
        }
    }

    @Test("belongsToLoader returns nil for non-existent parent")
    func belongsToLoaderReturnsNilForMissing() async throws {
        try await withRelationshipTables { repo in
            let bogusId = UUID()

            let loader: @Sendable (GenericDatabaseRepo) async throws -> RelUser? =
                SpectroLazyRelation<RelUser?>.belongsToLoader(
                    foreignKeyValue: bogusId
                )

            var relation = SpectroLazyRelation<RelUser?>(
                relationshipInfo: RelationshipInfo(
                    name: "relUser",
                    relatedTypeName: "RelUser",
                    kind: .belongsTo,
                    foreignKey: "rel_user_id"
                )
            ).withLoader(loader)

            let user = try await relation.load(using: repo)
            #expect(user == nil)
            #expect(relation.isLoaded)
        }
    }
}
}
