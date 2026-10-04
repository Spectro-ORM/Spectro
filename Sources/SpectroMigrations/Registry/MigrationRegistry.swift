import Foundation
import Spectro
import SpectroCommon

public struct SQLMigrations: Sendable {
    internal let directory: URL?
    internal let label: String

    public init(bundle: Bundle, directory: String) {
        label = directory
        if !directory.isEmpty, !directory.hasPrefix("/"), !directory.split(separator: "/").contains("..") {
            self.directory = bundle.resourceURL?.appendingPathComponent(directory, isDirectory: true)
        } else {
            self.directory = nil
        }
    }
}

internal enum RegistryEntry: Sendable {
    case swift(String, MigrationPlan)
    case sql(SQLMigrations)
}

public struct MigrationEntries: Sendable {
    internal let entries: [RegistryEntry]
    internal init(_ entries: [RegistryEntry]) { self.entries = entries }
}

@resultBuilder
public enum MigrationRegistryBuilder {
    public static func buildExpression<M: Migration>(_ migration: M) -> MigrationEntries {
        MigrationEntries([.swift(M.id, migration.change)])
    }
    public static func buildExpression(_ sql: SQLMigrations) -> MigrationEntries { MigrationEntries([.sql(sql)]) }
    public static func buildBlock(_ entries: MigrationEntries...) -> MigrationEntries { combine(entries) }
    public static func buildOptional(_ entries: MigrationEntries?) -> MigrationEntries { entries ?? MigrationEntries([]) }
    public static func buildEither(first: MigrationEntries) -> MigrationEntries { first }
    public static func buildEither(second: MigrationEntries) -> MigrationEntries { second }
    public static func buildArray(_ entries: [MigrationEntries]) -> MigrationEntries { combine(entries) }
    private static func combine(_ entries: [MigrationEntries]) -> MigrationEntries { MigrationEntries(entries.flatMap(\.entries)) }
}

/// An immutable snapshot of explicitly registered declarations and resource locations.
public struct MigrationRegistry: Sendable {
    private let entries: MigrationEntries

    public init(@MigrationRegistryBuilder _ content: () -> MigrationEntries) { entries = content() }

    public func sources() throws -> [MigrationSource] {
        let sources = try entries.entries.map { entry -> MigrationSource in
            switch entry {
            case .swift(let id, let plan):
                return .prepared([try MigrationCompiler.prepare(id: id, plan: plan)])
            case .sql(let resource):
                var isDirectory: ObjCBool = false
                guard let url = resource.directory,
                      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw MigrationPlanningError(reason: "Missing SQL resource directory: \(resource.label)")
                }
                return .sqlDirectory(url)
            }
        }
        _ = try MigrationCatalog.load(sources: sources)
        return sources
    }
}

