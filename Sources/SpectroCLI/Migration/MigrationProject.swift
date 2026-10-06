import ArgumentParser
import Foundation

struct MigrationProject: Sendable {
    struct Descriptor: Codable {
        struct Migrations: Codable { let product: String; let sourceDirectory: String }
        let formatVersion: Int
        let migrations: Migrations
    }
    let root: URL
    let product: String
    let sourceDirectory: URL

    static func packageRoot(from start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL? {
        var current = start.resolvingSymlinksInPath().standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) { return current }
            // Foundation can append /.. when removing the last component of /.
            // Stop explicitly so SQL-only projects never walk above the root.
            guard current.path != "/" else { return nil }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    static func discover() throws -> MigrationProject? {
        guard let root = packageRoot() else { return nil }
        let file = root.appendingPathComponent(".spectro.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let descriptor: Descriptor
        do { descriptor = try JSONDecoder().decode(Descriptor.self, from: Data(contentsOf: file)) }
        catch { throw ValidationError("Invalid .spectro.json: expected formatVersion and migrations.product/sourceDirectory.") }
        guard descriptor.formatVersion == 1 else { throw ValidationError("Unsupported .spectro.json formatVersion; expected 1.") }
        let product = descriptor.migrations.product
        guard !product.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !product.hasPrefix("-"),
              !product.contains("\0"), !product.contains("\n"), !product.contains("\r") else {
            throw ValidationError("The migration product must be nonempty and cannot start with a dash or contain control characters.")
        }
        let directory = try containedPath(descriptor.migrations.sourceDirectory, root: root)
        return MigrationProject(root: root, product: product, sourceDirectory: directory)
    }

    static func containedPath(_ path: String, root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\0") else {
            throw ValidationError("Migration sourceDirectory must be a relative path inside the package.")
        }
        // Resolve each existing ancestor even when the final destination does not exist yet.
        let resolved = path.split(separator: "/").reduce(root.resolvingSymlinksInPath()) {
            $0.appendingPathComponent(String($1)).resolvingSymlinksInPath().standardizedFileURL
        }
        guard resolved.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw ValidationError("Migration sourceDirectory escapes the package.")
        }
        return resolved
    }

    static func validateTypeName(_ name: String) throws {
        guard name.range(of: #"^[A-Z][A-Za-z0-9]*$"#, options: .regularExpression) != nil,
              !["Self", "Any", "AnyObject"].contains(name) else {
            throw ValidationError("Use a PascalCase Swift name containing only ASCII letters and digits.")
        }
    }
}
