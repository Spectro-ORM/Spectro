import SpectroMigrations
import FixtureDefinitions

@main
struct MissingMigrations {
    static func main() async {
        await MigrationCommand.main(migrations: FixtureCatalog.missingLatest)
    }
}
