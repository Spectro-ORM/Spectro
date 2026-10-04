// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SpectroIssueTracker",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "Spectro", path: "../.."),
        .package(url: "https://github.com/Maartz/swift-peregrine.git", exact: "1.2.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.31.0"),
    ],
    targets: [
        .executableTarget(name: "IssueTracker", dependencies: [
            .product(name: "SpectroKit", package: "Spectro"),
            .product(name: "Peregrine", package: "swift-peregrine"),
            .product(name: "PostgresNIO", package: "postgres-nio"),
        ]),
        .executableTarget(
            name: "IssueTrackerMigrations",
            dependencies: [.product(name: "SpectroMigrations", package: "Spectro")],
            resources: [.copy("LegacySQL")]
        ),
    ]
)
