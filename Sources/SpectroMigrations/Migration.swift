import SpectroCommon

/// A deterministic, historical schema change. The generator assigns its ID once.
public protocol Migration: Sendable {
    static var id: String { get }
    @MigrationBuilder var change: MigrationPlan { get }
}

/// A value that contributes operations to a migration.
public protocol MigrationStep: Sendable {
    var migrationPlan: MigrationPlan { get }
}
