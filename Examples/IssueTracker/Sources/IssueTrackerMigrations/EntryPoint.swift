import SpectroMigrations

@main
struct IssueTrackerMigrations {
    static func main() async {
        await MigrationCommand.main(migrations: MigrationRegistry {
            SQLMigrations(bundle: .module, directory: "LegacySQL")
            AddIssueArchive()
        })
    }
}
