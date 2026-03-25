import Foundation
import Testing
@testable import Spectro

/// Tests for the Ecto-style NotLoaded assertion behavior.
/// These are unit tests — no database needed.
@Suite("NotLoaded Assertions")
struct NotLoadedAssertionTests {

    @Test("isLoaded is false on fresh HasMany")
    func hasManyNotLoaded() {
        let wrapper = HasMany<TestPost>()
        #expect(wrapper.projectedValue.isLoaded == false)
    }

    @Test("isLoaded is true after setting wrappedValue")
    func hasManyLoadedAfterSet() {
        var wrapper = HasMany<TestPost>()
        wrapper.wrappedValue = []
        #expect(wrapper.projectedValue.isLoaded == true)
    }

    @Test("isLoaded is true after preload injection via projectedValue")
    func hasManyLoadedAfterInjection() {
        var wrapper = HasMany<TestPost>()
        wrapper.projectedValue = SpectroLazyRelation(
            loaded: [TestPost](),
            relationshipInfo: wrapper.projectedValue.relationshipInfo
        )
        #expect(wrapper.projectedValue.isLoaded == true)
    }

    @Test("isLoaded is false on fresh BelongsTo")
    func belongsToNotLoaded() {
        let wrapper = BelongsTo<TestUser>()
        #expect(wrapper.projectedValue.isLoaded == false)
    }

    @Test("isLoaded is true after setting BelongsTo wrappedValue")
    func belongsToLoadedAfterSet() {
        var wrapper = BelongsTo<TestUser>()
        wrapper.wrappedValue = nil
        #expect(wrapper.projectedValue.isLoaded == true)
    }

    @Test("isLoaded is false on fresh HasOne")
    func hasOneNotLoaded() {
        let wrapper = HasOne<TestUser>()
        #expect(wrapper.projectedValue.isLoaded == false)
    }

    @Test("isLoaded is true after setting HasOne wrappedValue")
    func hasOneLoadedAfterSet() {
        var wrapper = HasOne<TestUser>()
        wrapper.wrappedValue = nil
        #expect(wrapper.projectedValue.isLoaded == true)
    }

    @Test("isLoaded is false on fresh ManyToMany")
    func manyToManyNotLoaded() {
        let wrapper = ManyToMany<TestUser>()
        #expect(wrapper.projectedValue.isLoaded == false)
    }

    @Test("isLoaded is true after setting ManyToMany wrappedValue")
    func manyToManyLoadedAfterSet() {
        var wrapper = ManyToMany<TestUser>()
        wrapper.wrappedValue = []
        #expect(wrapper.projectedValue.isLoaded == true)
    }
}
