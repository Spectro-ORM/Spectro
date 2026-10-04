import Foundation
import Testing
import Spectro
import SpectroCommon
@testable import SpectroMigrations

@Suite("Migration registry")
struct RegistryTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
        func read() -> Int { lock.lock(); defer { lock.unlock() }; return value }
    }
    struct Counted: Migration {
        static let id = "1700000020_counted"
        let count: Counter
        var change: MigrationPlan {
            let _ = count.increment()
            SQL(up: "SELECT 1", down: "SELECT 2")
        }
    }

    @Test("Registry snapshots bodies once and sorts execution independently")
    func snapshot() throws {
        let counter = Counter()
        let registry = MigrationRegistry { CreateUsers(); Counted(count: counter) }
        #expect(counter.read() == 1)
        for _ in 0..<2 {
            let entries = try MigrationCatalog.load(sources: registry.sources())
            #expect(entries.map(\.version) == [Counted.id, CreateUsers.id])
        }
        #expect(counter.read() == 1)
    }

    @Test("Duplicate registration fails before a database is opened")
    func duplicate() {
        let registry = MigrationRegistry { CreateUsers(); CreateUsers() }
        #expect(throws: MigrationPlanningError.self) { try registry.sources() }
        let mixed = MigrationRegistry {
            SQLMigrations(bundle: .module, directory: "LegacySQL")
            CreateUsers()
        }
        #expect(throws: MigrationPlanningError.self) { try mixed.sources() }
    }

    @Test("Resources must exist in the explicitly supplied bundle")
    func missingResource() {
        let registry = MigrationRegistry { SQLMigrations(bundle: .main, directory: "Missing-\(UUID())") }
        #expect(throws: MigrationPlanningError.self) { try registry.sources() }
    }
}
