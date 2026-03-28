import Foundation
import Testing
@testable import Spectro

// MARK: - Test Schemas for Encodable Verification

@Schema("enc_products")
struct EncProduct {
    @ID var id: UUID
    @Column var name: String
    @Column var price: Double
    @Column var isAvailable: Bool
    @Column var stockCount: Int
    @Column var details: String?
    @Timestamp var createdAt: Date
}

@Schema("enc_custom_keys")
struct EncCustomKey {
    @ID var id: UUID
    @Column("display") var displayName: String = ""
    @Column var normalField: String
}

@Schema("enc_no_encode", encodable: false)
struct EncNoEncode {
    @ID var id: UUID
    @Column var secret: String
}

// MARK: - Tests

@Suite("Encodable Schema")
struct EncodableSchemaTests {

    // MARK: - Basic Encoding

    @Test("All scalar field types encode correctly")
    func testAllFieldTypesEncode() throws {
        var product = EncProduct()
        product.id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        product.name = "Widget"
        product.price = 9.99
        product.isAvailable = true
        product.stockCount = 42
        product.details = "A fine widget"
        product.createdAt = Date(timeIntervalSince1970: 0)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(product)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["id"] as? String == "12345678-1234-1234-1234-123456789ABC")
        #expect(json["name"] as? String == "Widget")
        #expect(json["price"] as? Double == 9.99)
        #expect(json["is_available"] as? Bool == true)
        #expect(json["stock_count"] as? Int == 42)
        #expect(json["details"] as? String == "A fine widget")
        #expect(json["created_at"] != nil)
    }

    @Test("Snake case keys are produced from camelCase property names")
    func testSnakeCaseKeys() throws {
        let product = EncProduct()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(product)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // camelCase → snake_case
        #expect(json.keys.contains("is_available"))
        #expect(json.keys.contains("stock_count"))
        #expect(json.keys.contains("created_at"))
        // No camelCase keys leaked
        #expect(!json.keys.contains("isAvailable"))
        #expect(!json.keys.contains("stockCount"))
        #expect(!json.keys.contains("createdAt"))
    }

    // MARK: - Column Name Override

    @Test("@Column(\"custom\") override produces the custom JSON key")
    func testColumnNameOverride() throws {
        var item = EncCustomKey()
        item.displayName = "My Label"
        item.normalField = "normal"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // @Column("display") overrides the key (not snake_case "display_name")
        #expect(json["display"] as? String == "My Label")
        #expect(json["display_name"] == nil)
        // Normal field uses snake_case
        #expect(json["normal_field"] as? String == "normal")
    }

    // MARK: - Optional Fields

    @Test("Optional field omitted when nil")
    func testOptionalNilOmitted() throws {
        var product = EncProduct()
        product.details = nil

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(product)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["details"] == nil)
    }

    @Test("Optional field encoded when present")
    func testOptionalPresentEncoded() throws {
        var product = EncProduct()
        product.details = "Has value"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(product)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["details"] as? String == "Has value")
    }

    // MARK: - Relationship Encoding

    @Test("Relationship keys omitted when not loaded")
    func testRelationshipNotLoadedOmitted() throws {
        var user = RelUser()
        // The macro init sets self.posts = [] which marks the relation as .loaded([]).
        // To test .notLoaded behavior, reset relations to their unloaded state.
        user.$posts = SpectroLazyRelation<[RelPost]>(relationshipInfo: user.$posts.relationshipInfo)
        user.$profile = SpectroLazyRelation<RelProfile?>(relationshipInfo: user.$profile.relationshipInfo)
        user.$tags = SpectroLazyRelation<[RelTag]>(relationshipInfo: user.$tags.relationshipInfo)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Relationships not loaded → keys omitted
        #expect(json["posts"] == nil)
        #expect(json["profile"] == nil)
        #expect(json["tags"] == nil)
        // Scalar fields still present
        #expect(json["id"] != nil)
        #expect(json["name"] != nil)
        #expect(json["email"] != nil)
    }

    @Test("HasMany relationship encoded when loaded")
    func testHasManyLoadedEncoded() throws {
        var user = RelUser()
        user.name = "Alice"
        user.email = "alice@test.com"

        var post = RelPost()
        post.title = "Hello"
        post.body = "World"
        user.$posts = user.$posts.withLoaded([post])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["posts"] != nil)
        if let posts = json["posts"] as? [[String: Any]] {
            #expect(posts.count == 1)
            #expect(posts[0]["title"] as? String == "Hello")
        } else {
            Issue.record("Expected posts to be an array of dictionaries")
        }
    }

    @Test("HasMany loaded with empty array encodes as empty array")
    func testHasManyLoadedEmptyArray() throws {
        var user = RelUser()
        user.$posts = user.$posts.withLoaded([])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // .loaded([]) should encode as empty array, NOT omit the key
        #expect(json["posts"] != nil)
        if let posts = json["posts"] as? [[String: Any]] {
            #expect(posts.isEmpty)
        } else {
            Issue.record("Expected posts to be an empty array")
        }
    }

    @Test("BelongsTo relationship encoded when loaded")
    func testBelongsToLoadedEncoded() throws {
        var post = RelPost()
        post.title = "My Post"

        var parentUser = RelUser()
        parentUser.name = "Bob"
        post.$relUser = post.$relUser.withLoaded(parentUser)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(post)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["rel_user"] != nil)
        if let relUser = json["rel_user"] as? [String: Any] {
            #expect(relUser["name"] as? String == "Bob")
        } else {
            Issue.record("Expected rel_user to be a dictionary")
        }
    }

    @Test("ManyToMany relationship encoded when loaded")
    func testManyToManyLoadedEncoded() throws {
        var user = RelUser()
        user.name = "Charlie"

        var tag = RelTag()
        tag.name = "swift"
        user.$tags = user.$tags.withLoaded([tag])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["tags"] != nil)
        if let tags = json["tags"] as? [[String: Any]] {
            #expect(tags.count == 1)
            #expect(tags[0]["name"] as? String == "swift")
        } else {
            Issue.record("Expected tags to be an array")
        }
    }

    // MARK: - Encodable Opt-out

    @Test("Schema with encodable: false does not conform to Encodable")
    func testEncodableOptOut() {
        let secret = EncNoEncode()
        #expect(!(secret is any Encodable))
    }

    // MARK: - Round-trip Verification

    @Test("JSONEncoder round-trips all field types correctly")
    func testRoundTripEncoding() throws {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let fixedId = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!

        var product = EncProduct()
        product.id = fixedId
        product.name = "Gadget"
        product.price = 19.95
        product.isAvailable = false
        product.stockCount = 7
        product.details = "Shiny"
        product.createdAt = fixedDate

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(product)
        let jsonString = String(data: data, encoding: .utf8)!

        // Decode back to verify structure
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["id"] as? String == "AABBCCDD-1122-3344-5566-778899AABBCC")
        #expect(json["name"] as? String == "Gadget")
        #expect(json["price"] as? Double == 19.95)
        #expect(json["is_available"] as? Bool == false)
        #expect(json["stock_count"] as? Int == 7)
        #expect(json["details"] as? String == "Shiny")

        // Verify the date is ISO 8601
        #expect(jsonString.contains("1970") == false) // Not epoch
        #expect(json["created_at"] is String) // ISO 8601 string
    }
}
