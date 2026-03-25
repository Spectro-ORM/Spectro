import Foundation
import Testing
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Macro Loader Injection")
struct MacroLoaderInjectionTests {

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

    // MARK: - HasMany auto-injection

    @Test("HasMany loader is auto-injected by @Schema macro on query")
    func testHasManyLoaderAutoInjectedOnQuery() async throws {
        try await withRelationshipTables { repo in
            // Insert a user with two posts
            let alice = try await repo.insert(RelUser(name: "Alice", email: "alice@test.com"))
            let _ = try await repo.insert(RelPost(title: "Post A", body: "Body A", relUserId: alice.id))
            let _ = try await repo.insert(RelPost(title: "Post B", body: "Body B", relUserId: alice.id))

            // Fetch the user via repo.get() — no .preload() call
            guard let fetchedUser = try await repo.get(RelUser.self, id: alice.id) else {
                Issue.record("Expected to find user by ID")
                return
            }

            // The @Schema macro should have injected a hasManyLoader into $posts
            // during build(from:). Call load(using:) without any manual withLoader.
            var postsRelation = fetchedUser.$posts
            let posts = try await postsRelation.load(using: repo)

            #expect(posts.count == 2)
            let titles = Set(posts.map(\.title))
            #expect(titles.contains("Post A"))
            #expect(titles.contains("Post B"))
        }
    }

    // MARK: - BelongsTo auto-injection

    @Test("BelongsTo loader is auto-injected by @Schema macro on query")
    func testBelongsToLoaderAutoInjectedOnQuery() async throws {
        try await withRelationshipTables { repo in
            // Insert a user and a post belonging to them
            let alice = try await repo.insert(RelUser(name: "Alice", email: "alice@test.com"))
            let post = try await repo.insert(RelPost(title: "Alice's Post", body: "Content", relUserId: alice.id))

            // Fetch the post via repo.get() — no .preload() call
            guard let fetchedPost = try await repo.get(RelPost.self, id: post.id) else {
                Issue.record("Expected to find post by ID")
                return
            }

            // The @Schema macro should have injected a belongsToLoader into $relUser
            // during build(from:). Call load(using:) without any manual withLoader.
            var userRelation = fetchedPost.$relUser
            let user = try await userRelation.load(using: repo)

            #expect(user != nil)
            #expect(user?.name == "Alice")
            #expect(user?.email == "alice@test.com")
        }
    }

    // MARK: - HasOne auto-injection

    @Test("HasOne loader is auto-injected by @Schema macro on query")
    func testHasOneLoaderAutoInjectedOnQuery() async throws {
        try await withRelationshipTables { repo in
            // Insert a user and a profile for them
            let alice = try await repo.insert(RelUser(name: "Alice", email: "alice@test.com"))
            let _ = try await repo.insert(RelProfile(bio: "Alice's bio", relUserId: alice.id))

            // Fetch the user via repo.get() — no .preload() call
            guard let fetchedUser = try await repo.get(RelUser.self, id: alice.id) else {
                Issue.record("Expected to find user by ID")
                return
            }

            // The @Schema macro should have injected a hasOneLoader into $profile
            // during build(from:). Call load(using:) without any manual withLoader.
            var profileRelation = fetchedUser.$profile
            let profile = try await profileRelation.load(using: repo)

            #expect(profile != nil)
            #expect(profile?.bio == "Alice's bio")
        }
    }

    // MARK: - Empty result from loader

    @Test("HasMany loader returns empty array when no related records exist")
    func testLoaderReturnsEmptyForNoRelated() async throws {
        try await withRelationshipTables { repo in
            // Insert a user with NO posts
            let charlie = try await repo.insert(RelUser(name: "Charlie", email: "charlie@test.com"))

            // Fetch the user via repo.get()
            guard let fetchedUser = try await repo.get(RelUser.self, id: charlie.id) else {
                Issue.record("Expected to find user by ID")
                return
            }

            // The loader should be injected, and when called it should return
            // an empty array rather than throwing.
            var postsRelation = fetchedUser.$posts
            let posts = try await postsRelation.load(using: repo)

            #expect(posts.isEmpty)
            #expect(postsRelation.isLoaded)
        }
    }
}
}
