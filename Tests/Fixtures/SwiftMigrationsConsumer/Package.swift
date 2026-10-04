// swift-tools-version: 6.0
import PackageDescription

let executables = ["FixtureMigrations", "MissingMigrations", "DuplicateMigrations", "SlowMigrations"]
let package = Package(
    name: "SwiftMigrationsConsumer",
    platforms: [.macOS(.v13)],
    products: executables.map { .executable(name: $0, targets: [$0]) },
    dependencies: [.package(name: "Spectro", path: "../../..")],
    targets: [
        .target(name: "FixtureDefinitions",
            dependencies: [.product(name: "SpectroMigrations", package: "Spectro")],
            resources: [.copy("LegacySQL")])
    ] + executables.map {
        .executableTarget(name: $0, dependencies: [
            "FixtureDefinitions", .product(name: "SpectroMigrations", package: "Spectro")
        ])
    }
)
