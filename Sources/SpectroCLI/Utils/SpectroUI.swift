@preconcurrency import Noora

enum SpectroUI {
    static let noora = Noora(theme: Theme(
        primary: "6C63FF",
        secondary: "A78BFA",
        muted: "6B7280",
        accent: "F59E0B",
        danger: "EF4444",
        success: "10B981",
        info: "3B82F6",
        selectedRowText: "FFFFFF",
        selectedRowBackground: "4C1D95"
    ))

    // MARK: - Fun Messages

    static let migrationCreatedMessages = [
        "Fresh migration dropped.",
        "New migration, who dis?",
        "New migration ready for takeoff!",
        "Migration created!",
    ]

    static let migrationAppliedMessages = [
        "Migration applied!",
        "Migration complete. All systems go!",
        "Migration applied successfully.",
        "Smooth — migration applied.",
    ]

    static let rollbackAppliedMessages = [
        "Rollback complete.",
        "Rolled back successfully.",
        "Rollback done.",
        "Rollback complete.",
    ]

    static func randomMigrationCreated() -> String {
        migrationCreatedMessages.randomElement()!
    }

    static func randomMigrationApplied() -> String {
        migrationAppliedMessages.randomElement()!
    }

    static func randomRollbackApplied() -> String {
        rollbackAppliedMessages.randomElement()!
    }
}
