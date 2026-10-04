import SpectroMigrations
import FixtureDefinitions

@main
struct SlowMigrations {
    static func main() async {
        await MigrationCommand.main(migrations: FixtureCatalog.slow)
    }
}
