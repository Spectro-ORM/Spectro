import SpectroMigrations

@main
struct FixtureMigrations {
    static func main() async {
        await MigrationCommand.main(migrations: MigrationRegistry {
            AddLegacyPriority()
            SQLMigrations(bundle: .module, directory: "LegacySQL")
            CreateFixtureUsers()
        })
    }
}

