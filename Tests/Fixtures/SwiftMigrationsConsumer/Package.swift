// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMigrationsConsumer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FixtureMigrations", targets: ["FixtureMigrations"])],
    dependencies: [.package(name: "Spectro", path: "../../..")],
    targets: [
        .executableTarget(
            name: "FixtureMigrations",
            dependencies: [.product(name: "SpectroMigrations", package: "Spectro")],
            resources: [.copy("LegacySQL")]
        )
    ]
)

