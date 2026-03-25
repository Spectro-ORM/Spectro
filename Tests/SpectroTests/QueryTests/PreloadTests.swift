import Foundation
import Testing
import SpectroCommon
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Preload")
struct PreloadTests {

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
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "rel_tags" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL DEFAULT ''
            )
        """)
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "rel_user_tags" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "rel_user_id" UUID NOT NULL,
                "rel_tag_id" UUID NOT NULL
            )
        """)

        try await repo.executeRawSQL("TRUNCATE \"rel_user_tags\", \"rel_tags\", \"rel_profiles\", \"rel_posts\", \"rel_users\"")

        // Seed: Alice (2 posts, 1 profile), Bob (1 post, no profile)
        let alice = try await repo.insert(RelUser(name: "Alice", email: "alice@test.com"))
        let bob = try await repo.insert(RelUser(name: "Bob", email: "bob@test.com"))
        let _ = try await repo.insert(RelPost(title: "Alice Post 1", body: "Body 1", relUserId: alice.id))
        let _ = try await repo.insert(RelPost(title: "Alice Post 2", body: "Body 2", relUserId: alice.id))
        let _ = try await repo.insert(RelPost(title: "Bob Post 1", body: "Body 3", relUserId: bob.id))
        let _ = try await repo.insert(RelProfile(bio: "Alice's bio", relUserId: alice.id))

        // Seed tags and junction rows for M2M tests
        let tagSwift = try await repo.insert(RelTag(name: "swift"))
        let tagORM = try await repo.insert(RelTag(name: "orm"))
        let tagDB = try await repo.insert(RelTag(name: "database"))
        // Alice has swift + orm, Bob has swift + database
        let _ = try await repo.insert(RelUserTag(relUserId: alice.id, relTagId: tagSwift.id))
        let _ = try await repo.insert(RelUserTag(relUserId: alice.id, relTagId: tagORM.id))
        let _ = try await repo.insert(RelUserTag(relUserId: bob.id, relTagId: tagSwift.id))
        let _ = try await repo.insert(RelUserTag(relUserId: bob.id, relTagId: tagDB.id))

        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    // MARK: - HasMany

    @Test("Preload HasMany loads related entities per parent")
    func preloadHasMany() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$posts)
                .orderBy({ $0.name }, .asc)
                .all()

            #expect(users.count == 2)
            #expect(users[0].name == "Alice")
            #expect(users[0].posts.count == 2)
            #expect(users[1].name == "Bob")
            #expect(users[1].posts.count == 1)
        }
    }

    // MARK: - HasOne

    @Test("Preload HasOne loads single related entity")
    func preloadHasOne() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$profile)
                .orderBy({ $0.name }, .asc)
                .all()

            #expect(users.count == 2)
            #expect(users[0].name == "Alice")
            #expect(users[0].profile != nil)
            #expect(users[0].profile?.bio == "Alice's bio")
            #expect(users[1].name == "Bob")
            #expect(users[1].profile == nil)
        }
    }

    // MARK: - BelongsTo

    @Test("Preload BelongsTo loads parent entity")
    func preloadBelongsTo() async throws {
        try await withRelationshipTables { repo in
            let posts = try await repo.query(RelPost.self)
                .preload(\.$relUser)
                .orderBy({ $0.title }, .asc)
                .all()

            #expect(posts.count == 3)
            for post in posts {
                #expect(post.relUser != nil)
            }
            #expect(posts[0].relUser?.name == "Alice")
            #expect(posts[2].relUser?.name == "Bob")
        }
    }

    // MARK: - Chained Preloads

    @Test("Chained preloads load multiple relationships")
    func chainedPreloads() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$posts)
                .preload(\.$profile)
                .orderBy({ $0.name }, .asc)
                .all()

            #expect(users.count == 2)
            // Alice: 2 posts + profile
            #expect(users[0].posts.count == 2)
            #expect(users[0].profile?.bio == "Alice's bio")
            // Bob: 1 post + no profile
            #expect(users[1].posts.count == 1)
            #expect(users[1].profile == nil)
        }
    }

    // MARK: - Preload with Where

    @Test("Preload only runs on filtered parent set")
    func preloadWithWhere() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$posts)
                .where { $0.name == "Alice" }
                .all()

            #expect(users.count == 1)
            #expect(users[0].name == "Alice")
            #expect(users[0].posts.count == 2)
        }
    }

    // MARK: - Empty Result

    @Test("Preload on empty result set does not crash")
    func preloadEmptyResult() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$posts)
                .where { $0.name == "Nobody" }
                .all()

            #expect(users.isEmpty)
        }
    }

    // MARK: - First

    @Test("Preload with first returns single entity with relations")
    func preloadFirst() async throws {
        try await withRelationshipTables { repo in
            let user = try await repo.query(RelUser.self)
                .preload(\.$posts)
                .orderBy({ $0.name }, .asc)
                .first()

            #expect(user != nil)
            #expect(user?.name == "Alice")
            #expect(user?.posts.count == 2)
        }
    }

    // MARK: - Explicit FK

    @Test("Preload with explicit FK override")
    func preloadExplicitFK() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$posts, foreignKey: "relUserId")
                .orderBy({ $0.name }, .asc)
                .all()

            #expect(users.count == 2)
            #expect(users[0].posts.count == 2)
            #expect(users[1].posts.count == 1)
        }
    }

    // MARK: - ManyToMany

    @Test("Preload ManyToMany loads tags for users through junction table")
    func preloadManyToMany() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$tags)
                .orderBy({ $0.name }, .asc)
                .all()

            #expect(users.count == 2)
            // Alice has swift + orm
            #expect(users[0].name == "Alice")
            #expect(users[0].tags.count == 2)
            let aliceTagNames = Set(users[0].tags.map(\.name))
            #expect(aliceTagNames.contains("swift"))
            #expect(aliceTagNames.contains("orm"))
            // Bob has swift + database
            #expect(users[1].name == "Bob")
            #expect(users[1].tags.count == 2)
            let bobTagNames = Set(users[1].tags.map(\.name))
            #expect(bobTagNames.contains("swift"))
            #expect(bobTagNames.contains("database"))
        }
    }

    @Test("ManyToMany with empty junction returns empty arrays")
    func preloadManyToManyEmpty() async throws {
        try await withRelationshipTables { repo in
            // Insert a user with no tags
            let _ = try await repo.insert(RelUser(name: "Charlie", email: "charlie@test.com"))

            let users = try await repo.query(RelUser.self)
                .preload(\.$tags)
                .where { $0.name == "Charlie" }
                .all()

            #expect(users.count == 1)
            #expect(users[0].name == "Charlie")
            #expect(users[0].tags.isEmpty)
        }
    }

    @Test("ManyToMany with filtered parents only loads matching")
    func preloadManyToManyFiltered() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$tags)
                .where { $0.name == "Alice" }
                .all()

            #expect(users.count == 1)
            #expect(users[0].name == "Alice")
            #expect(users[0].tags.count == 2)
            let tagNames = Set(users[0].tags.map(\.name))
            #expect(tagNames.contains("swift"))
            #expect(tagNames.contains("orm"))
        }
    }

    @Test("ManyToMany chained with other preloads")
    func preloadManyToManyChained() async throws {
        try await withRelationshipTables { repo in
            let users = try await repo.query(RelUser.self)
                .preload(\.$posts)
                .preload(\.$tags)
                .orderBy({ $0.name }, .asc)
                .all()

            #expect(users.count == 2)
            // Alice: 2 posts + 2 tags
            #expect(users[0].posts.count == 2)
            #expect(users[0].tags.count == 2)
            // Bob: 1 post + 2 tags
            #expect(users[1].posts.count == 1)
            #expect(users[1].tags.count == 2)
        }
    }
}
}
