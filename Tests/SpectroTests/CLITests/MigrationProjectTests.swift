import Foundation
import Testing
@testable import SpectroCLI

@Suite("Migration project discovery")
struct MigrationProjectTests {
    @Test("Discovery stops at the filesystem root for Foundation directory URLs")
    func noPackageAncestor() throws {
        // FileManager's URL can use Foundation's legacy representation, whose
        // parent of / is /.. rather than /. Reconstructing the URL hides the bug.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spectro-no-package-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(MigrationProject.packageRoot(from: directory) == nil)
    }
}
