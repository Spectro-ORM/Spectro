import ArgumentParser
import Foundation
import Spectro
import SpectroCommon

internal struct MigrationCredentials: ParsableArguments {
    @Option(name: .long, help: "Override DB_USER.") var username: String?
    @Option(name: .long, help: "Override DB_PASSWORD.") var password: String?
    @Option(name: .long, help: "Override DB_NAME.") var database: String?

    func resolve(environment: [String: String], custom: DatabaseConfiguration? = nil) throws -> DatabaseConfiguration {
        func required(_ override: String?, _ key: String) throws -> String {
            guard let value = override ?? environment[key] else { throw SpectroError.missingEnvironmentVariable(key) }
            return value
        }
        let base: DatabaseConfiguration
        if let custom {
            base = custom
        } else {
            guard let port = Int(environment["DB_PORT"] ?? "5432"), (1...65535).contains(port) else {
                throw ValidationError("DB_PORT must be an integer between 1 and 65535.")
            }
            base = try DatabaseConfiguration(
                hostname: environment["DB_HOST"] ?? "localhost", port: port,
                username: required(username, "DB_USER"), password: required(password, "DB_PASSWORD"),
                database: required(database, "DB_NAME"))
        }
        guard (1...65535).contains(base.port) else { throw ValidationError("Database port must be between 1 and 65535.") }
        return DatabaseConfiguration(hostname: base.hostname, port: base.port, username: username ?? base.username,
            password: password ?? base.password, database: database ?? base.database,
            maxConnectionsPerEventLoop: base.maxConnectionsPerEventLoop, numberOfThreads: base.numberOfThreads,
            tlsConfiguration: base.tlsConfiguration)
    }
}

