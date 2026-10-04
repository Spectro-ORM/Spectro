import Foundation
import Testing
import Spectro
import SpectroCommon
@testable import SpectroMigrations

@Suite("Migration executable command")
struct CommandTests {
    struct UnexpectedConfigurationLoad: Error {}
    let registry = MigrationRegistry { CreateUsers() }

    @Test("Help and all offline plan variants never load configuration")
    func offline() async {
        for args in [[], ["--help"], ["plan"], ["plan", "--migration", CreateUsers.id, "--direction", "down"]] {
            let code = await MigrationCommand.run(arguments: args, migrations: registry,
                configuration: { throw UnexpectedConfigurationLoad() })
            #expect(code == 0)
        }
    }

    @Test("Unknown IDs, irreversible down, and negative steps are failures")
    func invalid() async {
        for args in [["plan", "--migration", "missing"], ["down", "--step", "-1"]] {
            let code = await MigrationCommand.run(arguments: args, migrations: registry,
                configuration: { throw UnexpectedConfigurationLoad() })
            #expect(code != 0)
        }
        let irreversible = await MigrationCommand.run(arguments: ["plan", "--direction", "down"],
            migrations: MigrationRegistry { ControlFlowTests.Destructive() })
        #expect(irreversible != 0)
    }

    @Test("Zero rollback is a no-op without database configuration")
    func zero() async {
        let code = await MigrationCommand.run(arguments: ["down", "--step", "0"], migrations: registry,
            configuration: { throw UnexpectedConfigurationLoad() })
        #expect(code == 0)
    }

    @Test("Environment validation is strict and credential overrides fill missing values")
    func configuration() throws {
        var options = try MigrationCredentials.parse([])
        options.username = "override"
        options.password = ""
        options.database = "overridden"
        let config = try options.resolve(environment: ["DB_PORT": "5433"])
        #expect(config.username == "override")
        #expect(config.password == "")
        #expect(config.database == "overridden")
        #expect(config.port == 5433)
        for port in ["abc", "0", "65536", "-1"] {
            #expect(throws: (any Error).self) { try options.resolve(environment: ["DB_PORT": port]) }
        }
        #expect(throws: (any Error).self) { try MigrationCredentials.parse([]).resolve(environment: [:]) }
    }

    @Test("Overrides preserve caller TLS and pool configuration")
    func customConfiguration() throws {
        var options = try MigrationCredentials.parse([])
        options.username = "override"
        let base = DatabaseConfiguration(hostname: "custom", port: 5434, username: "original", password: "secret",
            database: "customdb", maxConnectionsPerEventLoop: 2, numberOfThreads: 1,
            tlsConfiguration: .makeClientConfiguration())
        let config = try options.resolve(environment: [:], custom: base)
        #expect(config.username == "override")
        #expect(config.password == "secret")
        #expect(config.hostname == "custom")
        #expect(config.port == 5434)
        #expect(config.maxConnectionsPerEventLoop == 2)
        #expect(config.numberOfThreads == 1)
        #expect(config.tlsConfiguration != nil)
    }
}

