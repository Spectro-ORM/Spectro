import SpectroCommon

/// A deterministic, historical schema change. The generator assigns its ID once.
///
/// Describe historical names and types directly, independently of current models
/// and runtime environment. Add an instance to ``MigrationRegistry`` to register it.
public protocol Migration: Sendable {
    /// The stable full ID, in `epoch_seconds_lower_snake_case` form.
    static var id: String { get }
    /// The ordered operations, captured once when the migration is registered.
    @MigrationBuilder var change: MigrationPlan { get }
}

/// A value that contributes operations to a migration.
public protocol MigrationStep: Sendable {
    /// The immutable plan contributed by this operation.
    var migrationPlan: MigrationPlan { get }
}
