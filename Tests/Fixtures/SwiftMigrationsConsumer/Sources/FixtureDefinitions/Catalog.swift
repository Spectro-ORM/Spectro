import SpectroMigrations

public enum FixtureCatalog {
    public static var full: MigrationRegistry {
        MigrationRegistry {
            AddLegacyPriority()
            SQLMigrations(bundle: .module, directory: "LegacySQL")
            CreateFixtureUsers()
        }
    }
    public static var missingLatest: MigrationRegistry {
        MigrationRegistry {
            SQLMigrations(bundle: .module, directory: "LegacySQL")
            CreateFixtureUsers()
        }
    }
    public static var duplicate: MigrationRegistry {
        MigrationRegistry {
            SQLMigrations(bundle: .module, directory: "LegacySQL")
            DuplicateLegacy()
        }
    }
    public static var slow: MigrationRegistry { MigrationRegistry { SlowMigration() } }
}

private struct DuplicateLegacy: Migration {
    static let id = "1700000000_create_legacy_items"
    var change: MigrationPlan { SQL(up: "SELECT 1", down: "SELECT 2") }
}
private struct SlowMigration: Migration {
    static let id = "1700000003_slow"
    var change: MigrationPlan {
        SQL(up: "CREATE TABLE slow_probe (id INT); SELECT pg_sleep(20), 'spectro_swift_kill_probe'",
            down: "DROP TABLE slow_probe")
    }
}
