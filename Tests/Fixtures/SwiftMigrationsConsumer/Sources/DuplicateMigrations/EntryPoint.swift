import SpectroMigrations
import FixtureDefinitions

@main
struct DuplicateMigrations {
    static func main() async {
        await MigrationCommand.main(migrations: FixtureCatalog.duplicate)
    }
}
